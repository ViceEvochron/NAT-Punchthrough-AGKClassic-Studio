// Project: NAT-Punchthrough-GameClient
// Created: 2023-02-10

// Information and Instructions:
// This NAT-Punchthrough system works on the principle of a 'STUN' (Session Traversal of User Datagram Protocol [UDP] Through Network Address Translators [NAT]) server.
// An exchange server (the 'STUN') is set up on a system that has a required port open and forwarded so that other systems outside of the network can connect to it to exchange IP information.
// If the port is available on the exchange server, players can connect to it to report they either want to host a session or join an existing session.
// The exchange server then retrieves the IP information of the player and logs it for later broadcast to other players.  For the host, it logs the IP and stores the details
// so that they can be provided to other players (clients) who want to join.  For clients, the exchange server simply informs the host when a player wants to join and
// then exchanges IP addresses between the two players (host and joining client) so that they can then attempt to connect to each other directly at the same time.
// If the two players broadcast to each other on preset ports at the same time, the router will allow return traffic from the same system outbound traffic is sent to.
// As a result, the two players can then communicate directly with each other without having to manually open/forward ports in their routers.
// This approach also depends on routers retaining port paths along the way, so it won't work with symmetric NAT's or other uncommon NAT configurations.
// For most users with typical routers, this approach will generally work very well and is a common technique used in games and chat software.
// This is only for internet connections through routers.  It is not needed for LAN multiplayer connections since those ports are open.
// This system only completes the process up to connection.  Any further data exchange and player management is up to the developer.

// To use this system, follow these steps:
// 1 - Configure a system you want to use as a STUN server (also referred to as the 'list server' in the rem notes in the codebase).
//   > Remember to open/forward the needed port through your router so that other systems can connect to it (default port is 18889, change as desired with the PublicListPort value below.
//   > Make sure you know the external internet IP address of the system you are using for the list server.  Other players will need to know this to connect to it.
//   > You can make the list server's IP address available on a website that your game can retrieve or hard code it if desired.
// 2 - Change the PublicListIP$ value below to match the IP address of the list server so this program knows where to initially connect.
// 3 - If you want to change the host/client port (default 18890), change the UDPPort value in both this program and the server program.
//   > The host/client UDPPort needs to be different from the list server port.
// 4 - Once configured, start the list server program on the system dedicated to running it.
// 5 - Start the client program on any other system with a separate internet connection you want to use as host first.
//   > Press '1' to start a hosted session and you can optionally press the '0' key to verify your session is listed with the STUN server and is retrievable .
//   > Once you have verified your hosted session is listed with the server, you can start the client program on another system with a different internet connection you want to use as a joining player.
//   > Once the client program is running on another system you want to use to join with, simply press the '0' key first to retrieve the list of hosted sessions.
//   > If the session is retrieved and displayed, you can then press the '2' key to join the session.
//   > If the connection is successful, the client will display a confirmation message.

// show all errors
SetErrorMode(2)

// set window properties
SetWindowTitle( "NAT-PunchThrough-GameClient" )
SetWindowSize(1366,768,0)
SetWindowAllowResize( 1 )

// set display properties
SetOrientationAllowed(0,0,1,0)
SetSyncRate(0,0)
SetVSync(1)
SetScissor(0,0,0,0)
UseNewDefaultFonts( 1 )
SetPrintSize(2.5)

rem to display text details by default
global RenderMode as integer
RenderMode=1

rem to store server names
dim ServerName$[1000]

rem to store server IP and port values
dim ServerIP$[1000]
dim ServerPort[1000]
dim ServerLocalIP$[1000]
dim ServerLocalPort[1000]
dim ServerTime#[1000]  ` wait time before clearing the entry

dim zchat$[1000]  ` to store list of hosted sessions

global coredrv$ as string
coredrv$=""

nullc$=""

SetCameraPosition(1,0,0,0)
SetCameraRotation(1,0,0,0)

rem setup
` change this to be the IP address of the system running the list/STUN server
PublicListIP$="127.0.0.1"

` remember that port 18889 or whatever custom port you choose must be forwarded and open on the system running the list/STUN server
PublicListPort=18889

` this is the port to use for hosting and joining a session, must be different than the list/STUN server
UDPPort=18890

ntconnect=0
host=0

Sync()

tmm=(timer()*1000)
mxx=0



mpmain:
    Print("FPS: "+str(ScreenFPS()))
    Print("")
    Print("Press 0 to request server list...")
    Print("Press 1 to Host...")
    Print("Press 2 to Join...")
    
    ` 0 key for server list
    if GetRawKeyState(48)>0
        gosub GetServerList
        
        repeat
            Sync()
        until GetRawKeyState(48)=0
    endif
    
    ` 1 key for hosting
    if GetRawKeyState(49)>0 and ntconnect=0
        gosub StartHost
        
        repeat
            Sync()
        until GetRawKeyState(49)=0
    endif
    
    ` 2 key for joining as client
    if GetRawKeyState(50)>0 and mxx>0
        gosub StartClient
        
        repeat
            Sync()
        until GetRawKeyState(50)=0
    endif
    
    
    Print("")
    rem display list of servers
    rem this sample program only supports displaying and joining one at a time, but can support more than one with modification
    Print("----- Server List ----")
    if mxx>0
        for i = 1 to mxx
        Print(zchat$[i])
        next i
    endif

    Print("----- Status ----")
    rem update host as needed
    if ntconnect>0 and host=1
        Print("Hosting mode active, press 0 to check if hosted session is listed...")
        gosub UpdateHost
    endif
    
    Print("----- Messages ----")
    if HostLineA$<>nullc$ then Print(HostLineA$)
    if HostLineB$<>nullc$ then Print(HostLineB$)
    if ClientLineA$<>nullc$ then Print(ClientLineA$)
    
    rem update client as needed
    if ntconnect>0 and host=0
        Print("Client mode active and connection to host successful!")

        rem check for messages
        RecvPacketUDP=GetUDPNetworkMessage(MultiIDUDP)
        
        if RecvPacketUDP>0
            if RecvPacketUDP>0
                pc$=GetNetworkMessageString(RecvPacketUDP)
                ` can optionally check string value sent from host here
                
                DeleteNetworkMessage(RecvPacketUDP)  ` clear packet, you can also optionally loop this section to clear any remaining
            endif
        endif
        
        rem if client, send an occasional packet as a keep alive signal
        if abs(timer()-sendtmm#)>1.0
            SendPacket=CreateNetworkMessage()
            s$="+HelloUDP"
            AddNetworkMessageString(SendPacket,s$)
            SendUDPNetworkMessage(MultiIDUDP,SendPacket,add$,UDPPort)

            sendtmm#=timer()
        endif
    endif
    
    Render2DFront()
    SetRenderToScreen()
    Render3D()
    ` Render2DFront()
    Swap()
    
    if GetRawKeyState(27)>0
        end
    endif
    
    gosub SetFrameTMM
goto mpmain


GetServerList:
            if PublicListIP$<>nullc$
                if host=0 or PublicListUDP=0
                    s$=GetDeviceIP()
                    ServerListUDP=CreateUDPListener(s$,PublicListPort)  ` only use for listing server
                else
                    rem if hosting player wants to check the server list for their own listing, use the public list ID which should already be active
                    ServerListUDP=PublicListUDP
                endif

                rem next send signal to listing server to retrieve list of servers/hosts
                SendPacket=CreateNetworkMessage()
                s$="+List"
                AddNetworkMessageString(SendPacket,s$)
                SendUDPNetworkMessage(ServerListUDP,SendPacket,PublicListIP$,PublicListPort)

                Sync()
                
                tmm=timer()*1000
                eee=0
                mxx=0
                
                repeat
                    rem now listen for host/server listings
                    RecvPacket=GetUDPNetworkMessage(ServerListUDP)  ` to retrieve UDP messages
                    
                    if RecvPacket>0
                        rem process received packets here
                        pc$=GetNetworkMessageString(RecvPacket)

                        rem server status packets, resets timer for server list retrieval
                        rem some of this information is redundant/unnecessary, but is included in case a developer wants to analyze parameters and/or try different options
                        if pc$="+SERVERS"
                            s=GetNetworkMessageInteger(RecvPacket)  ` list index position of host/server
                            if s>1 then s=1  ` cap at 1 server for now
                            zchat$[s]=GetNetworkMessageString(RecvPacket)  ` name of server
                            ServerLocalIP$[s]=GetNetworkMessageString(RecvPacket)  ` local IP of server
                            ServerLocalPort[s]=GetNetworkMessageInteger(RecvPacket)  ` local of server
                            ServerIP$[s]=GetNetworkMessageString(RecvPacket)  ` public IP of server
                            ServerPort[s]=GetNetworkMessageInteger(RecvPacket)  ` public port of server
                            zchat$[s]=zchat$[s]+": "+ServerIP$[s]  ` IP of server
                            zchat$[s]=zchat$[s]+":"+str(ServerLocalPort[s])  ` local port of server, not really necessary unless troubleshooting/redesigning
                            if s>mxx then mxx=s
                            tmm=timer()*1000  ` reset timer to continue waiting longer
                        endif
                        
                        if pc$="+SERVERSDONE"
                            eee=1
                        endif
                        
                        DeleteNetworkMessage(RecvPacket)
                    endif
                    
                    Sync()
                until eee=1 or abs((timer()*1000)-tmm)>2800
                
                rem if no listed servers, set message to indicate
                if mxx=0
                    mxx=1
                    zchat$[mxx]="No public games detected..."
                endif
            endif
            
            rem delete listener as needed
            if host=0 or PublicListUDP=0
                if ServerListUDP>0
                    DeleteUDPListener(ServerListUDP)
                    ServerListUDP=0
                endif
            endif
return


StartHost:
    add$=GetDeviceIP()
    playername$="MyName"

    UDPPortListen=UDPPort
    MultiIDUDP=CreateUDPListener("anyip4",UDPPortListen)
    
    rem also create UDP listener for UDP packets
    s$=GetDeviceIP()
    PublicListUDP=CreateUDPListener(s$,PublicListPort)
    
    ntconnect=1
    host=1
return

UpdateHost:
    if PublicListUDP>0
        PublicListTime#=PublicListTime#-(1.0*fradjust#)
        
        if PublicListTime#<=0
            rem server needs to send this periodically to list system to stay on list
            rem some of this information is redundant/unnecessary, but is included in case a developer wants to analyze parameters and/or try different options
            SendPacket=CreateNetworkMessage()
            s$="+Server"
            AddNetworkMessageString(SendPacket,s$)
            AddNetworkMessageString(SendPacket,playername$)  ` send name of server, use pilot name for now
            AddNetworkMessageString(SendPacket,add$)  ` send local IP address of server
            AddNetworkMessageInteger(SendPacket,UDPPort)  ` send local port of server
            SendUDPNetworkMessage(PublicListUDP,SendPacket,PublicListIP$,PublicListPort)

            PublicListTime#=250
        endif
        
        rem also check for incoming message from listing server indicating that a client is trying to join, then repeatedly try to connect out to that client
        RecvPacket=GetUDPNetworkMessage(PublicListUDP)  ` to retrieve UDP messages
        
        if RecvPacket>0
            rem process received packets here
            pc$=GetNetworkMessageString(RecvPacket)
            
            rem server status packets, resets timer for this server
            rem some of this information is redundant/unnecessary, but is included in case a developer wants to analyze parameters and/or try different options
            if pc$="+CLIENTCONNECT"
                s$=GetNetworkMessageString(RecvPacket)  ` name of client trying to join
                tempLocalIP$=GetNetworkMessageString(RecvPacket)  ` local IP of client
                tempLocalPort=GetNetworkMessageInteger(RecvPacket)  ` local port of client
                tempIP$=GetNetworkMessageString(RecvPacket)  ` public IP of client
                tempPort=GetNetworkMessageInteger(RecvPacket)  ` public port of client
                
                ClientConnectTime#=48  ` try connecting for several seconds
                ClientConnectStage=4

                rem optionally show confirmation
                HostLineA$="Client Request Received: "+s$+" / IP="+tempIP$+GetCurrentTime()
            endif
            
            DeleteNetworkMessage(RecvPacket)
        endif
        
        rem attempting to connect to receive new client
        if ClientConnectTime#>0
            if trunc(ClientConnectTime#/10)=ClientConnectStage
                SendPacket=CreateNetworkMessage()
                s$="+UDPREPLY"
                AddNetworkMessageString(SendPacket,s$)
                SendUDPNetworkMessage(MultiIDUDP,SendPacket,tempIP$,UDPPort)  ` send packet out on UDP port to try and open connection

                rem optionally display each connection attempt
                HostLineB$="Attempt to connect to client: "+str(ClientConnectStage+1)+" / "+tempIP$
                
                ClientConnectStage=ClientConnectStage-1
            endif
            
            ClientConnectTime#=ClientConnectTime#-(1.0*fradjust#)
            if ClientConnectTime#<=0
                ClientConnectTime#=0
            endif
        endif
    endif
return



StartClient:
                rem attempt to connect to listed host/server
                if mxx>0 and ServerIP$[mxx]<>nullc$
                    
                    if PublicListUDP=0
                        s$=GetDeviceIP()
                        PublicListUDP=CreateUDPListener(s$,PublicListPort)
                    endif
                    
                    rem also create a listener for the connection to the host
                    MultiIDUDP=CreateUDPListener("anyip4",UDPPort)
                    
                    playername$="ClientName"
                    UDPPortListen=UDPPort
                    
                    r=0:s=200
                    zcount=0
                    tmm=timer()*1000
                    repeat
                        if abs((timer()*1000)-tmm)>s
                            rem signal to listing server that this player wants to connect to the selected hosted session
                            rem some of this information is redundant/unnecessary, but is included in case a developer wants to analyze parameters and/or try different options
                            SendPacket=CreateNetworkMessage()
                            s$="+Client"
                            AddNetworkMessageString(SendPacket,s$)
                            AddNetworkMessageString(SendPacket,playername$)  ` send name of client trying to connect
                            AddNetworkMessageString(SendPacket,ServerIP$[mxx])  ` send IP address of server they are trying to connect to
                            AddNetworkMessageInteger(SendPacket,ServerLocalPort[mxx])  ` send port of server they are trying to connect to
                            AddNetworkMessageString(SendPacket,s$)  ` send local IP address of this client
                            AddNetworkMessageInteger(SendPacket,UDPPort)  ` send port of this client
                            SendUDPNetworkMessage(PublicListUDP,SendPacket,PublicListIP$,PublicListPort)
                           
                            rem now send message to directly hosting player in the attempt to connect
                            SendPacket=CreateNetworkMessage()
                            s$="+UDPCHECK"
                            AddNetworkMessageString(SendPacket,s$)
                            SendUDPNetworkMessage(MultiIDUDP,SendPacket,ServerIP$[mxx],UDPPort)
                            
                            zcount=zcount+1
                            s=s+200
                        endif
                        
                        RecvPacket=GetUDPNetworkMessage(MultiIDUDP)
                        if RecvPacket>0
                            s$=GetNetworkMessageString(RecvPacket)
                            
                            if s$="+UDPREPLY"
                                r=1
                            endif
                        endif
                        
                        Print("Attempting to connect: "+ServerIP$[mxx]+" / "+str(UDPPort)+" / "+str(zcount))
                        
                        Render2DFront()
                        SetRenderToScreen()
                        Render3D()
                        ` Render2DFront()
                        Swap()
                    
                    until abs((timer()*1000)-tmm)>4800 or r=1
                    
                    
                    if r=0
                        ClientLineA$="Client connection failed..."
                        ntconnect=-1  ` to indicate attempt failed
                        
                        rem delete listener as needed
                        if PublicListUDP>0
                            DeleteUDPListener(PublicListUDP)
                            PublicListUDP=0
                        endif
                    else
                        s$=ServerIP$[mxx]
                        ClientLineA$="Client connection succeeded! ("+s$+")"
                        
                        ntconnect=1
                    endif
                endif
return



SetFrameTMM:
    rem reset the timer as needed with AGK since it is only a float and has precision limits
    if newtimer#=>10000
        s#=timer()-newtimer#
        ResetTimer() 
        newtimer#=timer()-s#
    endif
    
    oldtimer#=newtimer#
    newtimer#=timer()
    frametmm#=(newtimer#-oldtimer#)
    
    rem temporarily set an integer for 'newtimer' value in case it may be needed later
    newtimer=GetMilliseconds()
    newtmm=newtimer
    ptfreq=1000

    fradjust#=(fradjust#+((1.0/0.030303)*frametmm#))/2.0
    if fradjust#>5.9 then fradjust#=5.9
    if fradjust#<0.00001 then fradjust#=0.00001
    
    screenfps=(screenfps+(33.0/fradjust#))/2.0
return



