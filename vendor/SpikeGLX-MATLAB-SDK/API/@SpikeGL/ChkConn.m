% THIS FUNCTION IS PRIVATE AND SHOULD NOT BE CALLED BY OUTSIDE CODE!
%
function [sm] = ChkConn( sm )

    if( sm.in_chkconn )
        return;
    end

    sm.in_chkconn = 1;

    if( sm.handle == -1 )

        % Chipmunk: bound the initial TCP check; native connect has no deadline.
        probe = java.net.Socket();
        cleanup = onCleanup(@() probe.close());
        probe.connect(java.net.InetSocketAddress(sm.host, sm.port), 2000);
        clear cleanup
        sm.handle = CalinsNetMex( 'create', sm.host, sm.port );

        if( isempty( CalinsNetMex( 'connect', sm.handle ) ) )
            error( 'ChkConn: Unable to connect to server.' );
        end

        sm.ver = DoQuery( sm, 'GETVERSION' );

    else

        ok = CalinsNetMex( 'sendstring', sm.handle, sprintf( 'NOOP\n' ) );

        if( isempty( ok ) || isempty( CalinsNetMex( 'readline', sm.handle ) ) )

            % Chipmunk: let the GUI disconnect; never reconnect inside a poll.
            error( 'ChkConn: Connection lost. Reconnect explicitly.' );
        end
    end

    sm.in_chkconn = 0;
end
