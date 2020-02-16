Rebol [
    Title: "Web Server Scheme for Ren-C"
    Author: "Christopher Ross-Gill"
    Date: 13-Sep-2019
    File: %httpd.reb
    Home: https://github.com/rgchris/Scripts
    Version: 0.3.5
    Purpose: "An elementary Web Server scheme for creating fast prototypes"
    Rights: http://opensource.org/licenses/Apache-2.0
    Type: module
    Name: httpd
    History: [
        02-Feb-2019 0.3.5 "File argument for REDIRECT permits relative redirections"
        14-Dec-2018 0.3.4 "Add REFLECT handler (supports OPEN?); Redirect defaults to 303"
        16-Mar-2018 0.3.3 "Add COMPRESS? option"
        14-Mar-2018 0.3.2 "Closes connections (TODO: support Keep-Alive)"
        11-Mar-2018 0.3.1 "Reworked to support KILL?"
        23-Feb-2017 0.3.0 "Adapted from Rebol 2"
        06-Feb-2017 0.2.0 "Include HTTP Parser/Dispatcher"
        12-Jan-2017 0.1.0 "Original Version"
    ]
    Usage: {
        For a simple server that just returns HTTP envelope with "Hello":

            wait srv: open [scheme: 'httpd 8000 [render "Hello"]]

        Then point a browser at http://127.0.0.1:8000
    }
]

net-utils: reduce [
    comment [
        'net-log proc [message [block! text!]] [
            print either block? message [spaced message] [message]
        ]
    ]
    'net-log _
]

as-text: function [
    {Variant of AS TEXT! that scrubs out invalid UTF-8 sequences}
    binary [binary!]
    <local> mark
][
    mark: binary
    while [mark: try invalid-utf8? mark] [
        mark: change/part mark #{EFBFBD} 1
    ]
    to text! binary
]

sys/make-scheme [
    title: "HTTP Server"
    name: 'httpd

    spec: make system/standard/port-spec-head [port-id: actions: _]

    wake-client: function [
        return: [port!]
        event [event!]
    ][
        client: event/port
        
        probe client

        switch event/type [
            'read [
                net-utils/net-log unspaced [
                    "Instance [" client/locals/instance: me + 1 "]"
                ]

                case [
                    not client/locals/parent/locals/open? [
                        close client
                        client/locals/parent
                    ]

                    find client/data #{0D0A0D0A} [
                        transcribe client
                        dispatch client
                    ]

                    default [if not empty? client/data [
                        lib/write/append %logs/log.txt spaced [now/precise '| "inside event loop" '| client/locals/request/remote-addr/remote-ip '| to text! client/data newline ]
                        read client
                    ]]
                ]
            ]

            'wrote [
                ; !!! WROTE event used to be used for manual chunking
            ]

            'close [
                close client
            ]

            default [
                net-utils/net-log [
                    "Unexpected Client Event:" uppercase form event/type
                ]
            ]
        ]

        return client
    ]

    init: function [server [port!]] [
        spec: server/spec

        case [
            url? spec/ref []
            block? spec/actions []
            parse spec/ref [
                set-word! lit-word!
                integer! block!
            ][
                spec/port-id: spec/ref/3
                spec/actions: spec/ref/4
            ]
            fail "Server lacking core features."
        ]

        server/locals: make object! [
            handler: _
            subport: _
            open?: _
            clients: make block! 1024
        ]

        server/locals/handler: function [
            return: <void>
            request [object!]
            response [object!]
        ] compose [
            render: get in response 'render
            redirect: get in response 'redirect
            print: get in response 'print

            ((match block! server/spec/actions else [default-response]))
        ]

        server/locals/subport: make port! [scheme: 'tcp]

        server/locals/subport/spec/port-id: spec/port-id

        server/locals/subport/locals: make object! [
            instance: 0
            request: _
            response: _
            cookie: _ ;; "A=C"               ;; try this
            parent: :server
        ]

        server/locals/subport/awake: function [event [event!]] [
            switch event/type [
                'accept [
                    client: take event/port
                    client/awake: :wake-client
                    read client
                    event
                ]

                default [false]
            ]
        ]

        server/awake: function [e [event!]] [
            switch e/type [
                'close [
                    close e/port
                    true
                ]

                ; Since WRITE is asynchronous we can't catch errors via TRAP
                ; https://github.com/metaeducation/rebol-httpd/issues/4
                ;
                'error [
                    print ["Now we're in the SERVER/AWAKE with an error"]
                    -- err: ensure error! e/port/error

                    ; !!! No way to tell at the moment whether it was the
                    ; async WRITE of the header or the async WRITE of the
                    ; content that failed.  Better identity mechanism would
                    ; be needed for that.
                    ;
                    net-utils/net-log [
                        "Response header/content not sent to client."
                            "Reason:" err/message
                    ]

                    if not find [  ; !!! Should use ID codes, not strings!
                        "Connection reset by peer"
                        "Broken pipe"
                    ] err/message [
                        e/port/error: _
                        return true  ; Suppress these to keep server running
                    ]

                    return false  ; let default AWAKE handler do the FAIL
                ]

                default [false]
            ]
        ]

        server
    ]

    actor: [
        open: func [server [port!]] [
            net-utils/net-log ["Server running on port id" server/spec/port-id]
            open server/locals/subport
            server/locals/open?: yes
            server
        ]

        reflect: func [server [port!] property [word!]][
            switch property [
                'open? [
                    server/locals/open?
                ]

                fail [
                    "HTTPd port does not reflect this property:"
                        uppercase mold property
                ]
            ]
        ]

        close: func [server [port!]] [
            server/awake: server/locals/subport/awake: _
            server/locals/open?: no
            close server/locals/subport
            insert system/ports/system/data server
            ; ^^^ would like to know why...
            server
        ]
    ]

    default-response: [probe request/action]

    request-prototype: make object! [
        raw: _
        version: 1.1
        method: "GET"
        action: _
        headers: _
        http-headers: _
        oauth: _
        target: _
        binary: _
        content: _
        length: _
        timeout: _
        type: 'application/x-www-form-urlencoded
        server-software: unspaced [
            "Rebol/" system/product space "v" system/version
        ]
        server-name: _
        gateway-interface: _
        server-protocol: "http"
        server-port: _
        request-method: _
        request-uri: _
        path-info: _
        path-translated: _
        script-name: _
        query-string: _
        remote-host: _
        remote-addr:
        auth-type: _
        remote-user: _
        remote-ident: _
        content-type: _
        content-length: _
        error: _
    ]

    response-prototype: make object! [
        status: 404
        content: "Not Found"
        location: _
        type: "text/html"
        length: 0
        kill?: false
        close?: true
        compress?: false
        set-cookie: _ ; "C=D"

        render: method [response [text! binary!]] [
            status: 200
            content: response
        ]

        print: method [response [text!]] [
            status: 200
            content: response
            type: "text/plain"
        ]

        redirect: method [target [url! file!] /code [integer!]] [
            status: code: default [303]
            content: "Redirecting..."
            type: "text/plain"
            location: target
        ]
    ]

    transcribe: function [
        return: <void>
        client [port!]

      <static>

        request-action (["HEAD" | "GET" | "POST" | "PUT" | "DELETE"])

        request-path (use [chars] [
            chars: complement charset [#"^@" - #" " #"?"]
            [some chars]
        ])

        request-query (use [chars] [
            chars: complement charset [#"^@" - #" "]
            [any chars]  ; ANY instead of SOME (empty requests are legal)
        ])

        header-feed ([newline | cr lf])

        header-part (use [chars] [
            chars: complement charset [#"^(00)" - #"^(1F)"]
            [some chars any [header-feed some " " some chars]]
        ])

        header-name (use [chars] [
            chars: charset ["_-0123456789" #"a" - #"z" #"A" - #"Z"]
            [some chars]
        ])

        spaces-or-tabs (use [chars] [
            chars: charset " ^-"
            [some chars]
        ])

        header-prototype (make object! [
            Accept: "*/*"
            Connection: "close"
            User-Agent: _
            Content-Length: _
            Content-Type: _
            Authorization: _
            Range: _
            Referer: _
        ])
    ][
        client/locals/request: make request-prototype [
            parse raw: client/data [
                copy method request-action space
                copy request-uri [
                    copy target request-path opt [
                        "?" copy query-string request-query
                    ]
                ]
                spaces-or-tabs
                "HTTP/" copy version ["1.0" | "1.1"]
                header-feed
                (headers: make block! 10)
                some [
                    copy name header-name ":" any " "
                    copy value header-part header-feed
                    (
                        name: as-text name
                        value: as-text value
                        append headers reduce [to set-word! name value]
                        switch name [
                            "Content-Type" [content-type: value]
                            "Content-Length" [length: content-length: value]
                        ]
                    )
                ]
                header-feed content: to end (
                    binary: copy :content
                    content: does [content: as-text binary]
                )
            ] else [
                net-utils/net-log error: "Could Not Parse Request"
                return
            ]

            version: to text! :version
            request-method: method: to text! :method
            path-info: target: as-text :target
            action: spaced [method target]
            request-uri: as-text request-uri
            server-port: query/mode client 'local-port
            remote-addr: query/mode client 'remote-ip

            headers: make header-prototype
                http-headers: new-line/skip headers true 2

            type: all [
                text? type: headers/Content-Type
                ; append type ";"
                copy/part type find type ";"  ; if find is null, that voids the /part so it's just `copy type`
            ] else ["text/html"]

-- type

            length: content-length: attempt [to integer! length] else [0]

            net-utils/net-log action
        ]
    ]

    dispatch: function [
        return: <void>
        client [port!]

      <static>

        status-codes ([
            200 "OK"
            201 "Created"
            204 "No Content"

            301 "Moved Permanently"
            302 "Moved temporarily"
            303 "See Other"
            307 "Temporary Redirect"

            400 "Bad Request"
            401 "No Authorization"
            403 "Forbidden"
            404 "Not Found"
            411 "Length Required"
            
            500 "Internal Server Error"
            503 "Service Unavailable"
        ])

        build-header (function [response [object!]] [
            append make binary! 1024 spaced collect [
                if not find status-codes response/status [
                    response/status: 500
                ]
                any [
                    not match [binary! text!] response/content
                    empty? response/content
                ] then [
                    response/content: " "
                ]

                keep ["HTTP/1.1" response/status
                    select status-codes response/status]
                keep [cr lf "Content-Type:" response/type]
                keep [cr lf "Content-Length:"
                    length of as binary! response/content  ; bytes (not chars)
                ]
                if response/compress? [
                    keep [cr lf "Content-Encoding:" "gzip"]
                ]
                if response/location [
                    keep [cr lf "Location:" response/location]
                ]
                if response/close? [
                    keep [cr lf "Connection:" "close"]
                ]
                if not empty? response/set-cookie [
                    keep [cr lf "Set-Cookie:" response/set-cookie ]
                ]
                keep [cr lf "Access-Control-Allow-Origin: *"]
                keep [cr lf "Cache-Control:" "no-cache"]
                keep [cr lf cr lf]
            ]
        ])
    ][
        client/locals/response: response: make response-prototype []

        if object? client/locals/request [
            client/locals/parent/locals/handler client/locals/request response
        ] else [  ; don't crash on bad request
            response/status: 500
            response/type: "text/html"
            response/content: "Bad request."
        ]

        if response/compress? [
            response/content: gzip response/content
        ]

        ; Since WRITE is asynchronous we can't catch errors via TRAP
        ; https://github.com/metaeducation/rebol-httpd/issues/4
        ;
        write client hdr: build-header response  ; !!! is HDR var necessary?
        write client response/content
    ]
]
