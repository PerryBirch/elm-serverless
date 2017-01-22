port module ConnTests exposing (all)

import Conn.Fuzz as Fuzz exposing (testConn, testConnWith)
import Conn.PrivateTests
import Conn.TestHelpers exposing (..)
import ElmTestBDDStyle exposing (..)
import Expect exposing (..)
import Expect.Extra exposing (contain)
import Json.Encode as J
import Serverless.Conn exposing (..)
import Serverless.Conn.Types exposing (Sendable(..))
import Test exposing (..)


all : Test
all =
    describe "Conn"
        [ Conn.PrivateTests.all
        , responseTest
        ]


port fakeResponsePort : J.Value -> Cmd msg


responseTest : Test
responseTest =
    describe "Serverless.Conn"
        [ testConnWith Fuzz.body "body sets the response body" <|
            \( conn, val ) ->
                conn
                    |> body val
                    |> expectUnsent
                        (\resp ->
                            expect resp.body to equal val
                        )
        , testConnWith Fuzz.status "status sets the response status" <|
            \( conn, val ) ->
                conn
                    |> status val
                    |> expectUnsent
                        (\resp ->
                            expect resp.status to equal val
                        )
        , testConn "send sets the response to Sent" <|
            \conn ->
                let
                    ( newConn, _ ) =
                        conn |> send fakeResponsePort
                in
                    expect newConn.resp to equal Sent
        , testConn "send issues a side effect" <|
            \conn ->
                let
                    ( _, cmd ) =
                        conn |> send fakeResponsePort
                in
                    expect cmd to notEqual Cmd.none
        , testConn "send fails if the conn is already halted" <|
            \conn ->
                let
                    ( _, cmd ) =
                        { conn | resp = Sent } |> send fakeResponsePort
                in
                    expect cmd to equal Cmd.none
        , testConnWith Fuzz.header "headers adds a response header" <|
            \( conn, val ) ->
                conn
                    |> header val
                    |> expectUnsent
                        (\resp ->
                            expect resp.headers to contain val
                        )
        , testConnWith Fuzz.header "increases the response headers by 1" <|
            \( conn, val ) ->
                let
                    oldLength =
                        case conn.resp of
                            Unsent resp ->
                                resp.headers |> List.length

                            Sent ->
                                -2
                in
                    conn
                        |> header val
                        |> expectUnsent
                            (\resp ->
                                expect (resp.headers |> List.length) to equal (oldLength + 1)
                            )
        ]