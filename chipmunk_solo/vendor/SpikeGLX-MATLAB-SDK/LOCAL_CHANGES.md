# Chipmunk connection changes

`API/@SpikeGL/ChkConn.m` performs a two-second Java TCP preflight before creating a native socket and raises on an existing connection failure instead of reconnecting inside GUI polling. The Chipmunk client closes the failed handle; operators reconnect explicitly. Protocol commands and binary fetch framing are unchanged.
