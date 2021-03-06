module PoolTests exposing (all)

import ConnFuzz as Fuzz exposing (testConnWith, testReq)
import Dict
import ElmTestBDDStyle exposing (..)
import Expect exposing (..)
import Expect.Extra exposing (contain)
import Json.Encode as J
import Logging exposing (nullLogger)
import Serverless.Conn as Conn exposing (..)
import Serverless.Conn.Types exposing (..)
import Serverless.Pool exposing (..)
import Test exposing (..)
import Test.Extra exposing (..)
import TestHelpers exposing (..)
import TestTypes exposing (..)


all : Test
all =
    describe "Serverless.Pool"
        [ connectionPoolTests
        , requestDecoderTests
        , responseEncoderTests
        ]


connectionPoolTests : Test
connectionPoolTests =
    describe "Managing the Connection Pool"
        [ describe "emptyPool"
            [ it "creates a pool with no connections" <|
                expect
                    (emptyPool (Model 1) (Config "secret" |> Just)
                        |> .conn
                        |> Dict.size
                    )
                    to
                    equal
                    0
            ]
        , describe "addToPool"
            [ testReq "fails if the pool has no config" <|
                \req ->
                    expect
                        (emptyPool (Model 1) Nothing
                            |> addToPool nullLogger req
                            |> .conn
                            |> Dict.size
                        )
                        to
                        equal
                        0
            ]
        , describe "getFromPool"
            []
        , describe "replaceInPool"
            []
        ]


requestDecoderTests : Test
requestDecoderTests =
    describe "Request Decoding"
        [ describeDecoder "requestDecoder"
            requestDecoder
            [ ( "", FailsToDecode )
            , ( "{}", FailsToDecode )
            , ( """
            {
              "id": "some-id",
              "body": null,
              "headers": null,
              "host": "localhost",
              "method": "GeT",
              "path": "",
              "port": 80,
              "remoteIp": "127.0.0.1",
              "scheme": "http",
              "stage": "dev",
              "queryParams": null
            }
            """
              , DecodesTo
                    (Request
                        "some-id"
                        NoBody
                        []
                        "localhost"
                        GET
                        ""
                        80
                        (Ip4 ( 127, 0, 0, 1 ))
                        (Http Insecure)
                        "dev"
                        []
                    )
              )
            , ( """
            {
              "id": "some-other-id",
              "body": "foo bar",
              "headers": {
                "FRED": "VARLEy",
                "Content-Typo": "just/a/string"
              },
              "host": "127.0.0.1",
              "method": "post",
              "path": "/foo/bar/car",
              "port": 443,
              "remoteIp": "192.168.0.1",
              "scheme": "https",
              "stage": "staging",
              "queryParams": {}
            }
            """
              , DecodesTo
                    (Request
                        "some-other-id"
                        (TextBody "foo bar")
                        [ ( "content-typo", "just/a/string" )
                        , ( "fred", "VARLEy" )
                        ]
                        "127.0.0.1"
                        POST
                        "/foo/bar/car"
                        443
                        (Ip4 ( 192, 168, 0, 1 ))
                        (Http Secure)
                        "staging"
                        []
                    )
              )
            , ( """
            {
              "id": "random",
              "body": "{ \\"json\\": \\"encoded\\" }",
              "headers": {
                "Content-Type": "application/json"
              },
              "host": "127.0.0.1",
              "method": "post",
              "path": "/",
              "port": 443,
              "remoteIp": "192.168.0.1",
              "scheme": "https",
              "stage": "staging",
              "queryParams": {
                "FOO": "BAR",
                "car": "far"
              }
            }
            """
              , DecodesTo
                    (Request
                        "random"
                        (TextBody "{ \"json\": \"encoded\" }")
                        [ ( "content-type", "application/json" )
                        ]
                        "127.0.0.1"
                        POST
                        "/"
                        443
                        (Ip4 ( 192, 168, 0, 1 ))
                        (Http Secure)
                        "staging"
                        [ ( "car", "far" )
                        , ( "FOO", "BAR" )
                        ]
                    )
              )
            ]
        , describeDecoder "paramsDecoder"
            paramsDecoder
            [ ( "null", DecodesTo [] )
            , ( "{}", DecodesTo [] )
            , ( """{ "fOo": "baR " }""", DecodesTo [ ( "fOo", "baR " ) ] )
            , ( """{ "foo": 3 }""", FailsToDecode )
            ]
        , describeDecoder "bodyDecoder"
            bodyDecoder
            [ ( "null", DecodesTo NoBody )
            , ( "\"\"", DecodesTo (TextBody "") )
            , ( "\"foo bar\\ncar\"", DecodesTo (TextBody "foo bar\ncar") )
            , ( "\"{}\"", DecodesTo (TextBody "{}") )
            ]
        , describeDecoder "ipDecoder"
            ipDecoder
            [ ( "null", FailsToDecode )
            , ( "\"\"", FailsToDecode )
            , ( "\"1.2.3\"", FailsToDecode )
            , ( "\"1.2.3.4\"", DecodesTo (Ip4 ( 1, 2, 3, 4 )) )
            , ( "\"1.2.3.4.5\"", FailsToDecode )
            , ( "\"1.2.-3.4\"", FailsToDecode )
            ]
        , describeDecoder "methodDecoder"
            methodDecoder
            [ ( "null", FailsToDecode )
            , ( "\"\"", FailsToDecode )
            , ( "\"fizz\"", FailsToDecode )
            , ( "\"GET\"", DecodesTo GET )
            , ( "\"get\"", DecodesTo GET )
            , ( "\"gEt\"", DecodesTo GET )
            , ( "\"POST\"", DecodesTo POST )
            , ( "\"PUT\"", DecodesTo PUT )
            , ( "\"DELETE\"", DecodesTo DELETE )
            , ( "\"OPTIONS\"", DecodesTo OPTIONS )
            ]
        , describeDecoder "schemeDecoder"
            schemeDecoder
            [ ( "null", FailsToDecode )
            , ( "\"\"", FailsToDecode )
            , ( "\"http\"", DecodesTo (Http Insecure) )
            , ( "\"https\"", DecodesTo (Http Secure) )
            , ( "\"HTTP\"", DecodesTo (Http Insecure) )
            , ( "\"httpsx\"", FailsToDecode )
            ]
        , describe "initResponse"
            [ initResponseTest "is unsent" <|
                \_ ->
                    Expect.pass
            , initResponseTest "has no body" <|
                \resp -> expect resp.body to equal NoBody
            , initResponseTest "has a default no-cache header" <|
                \resp ->
                    expect resp.headers
                        to
                        contain
                        ( "cache-control"
                        , "max-age=0, private, must-revalidate"
                        )
            , initResponseTest "has an invalid status code" <|
                \resp -> expect resp.status to equal InvalidStatus
            ]
        , describe "encodeBody"
            [ it "encodes NoBody as null" <|
                expect (encodeBody NoBody) to equal J.null
            , it "encodes TextBody to plain text" <|
                expect (TextBody "abc123" |> encodeBody) to equal (J.string "abc123")
            ]
        , describe "encodeResponse"
            [ testConnWith Fuzz.header "contains the most recent header (when a header is set more than once)" <|
                \( conn, val ) ->
                    let
                        result =
                            conn |> Conn.header val |> getEncodedResponse
                    in
                        case result of
                            Ok resp ->
                                expect resp.headers to contain val

                            Err err ->
                                Expect.fail err
            ]
        ]


responseEncoderTests : Test
responseEncoderTests =
    describe "Response Encoding"
        [-- TODO
        ]
