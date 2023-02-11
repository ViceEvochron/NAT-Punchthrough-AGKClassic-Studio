// Project: NAT-Punchthrough-Server
// Created: 2023-02-10
// This program can run as a service in the background - set #Renderer to "None" and 'RenderMode' to 0 below
// This program displays a list of all active hosted session and provides NAT Punchthrough

// show all errors
SetErrorMode(2)

// set window properties
SetWindowTitle( "NAT-PunchThrough-Server" )

rem **** change to "None" to run as service when ready
` #Renderer "None"  ` for windowless mode
global RenderMode as integer
RenderMode=1  ` 0 = no graphics (run as service, also unrem #Renderer above), 1 = graphics

SetWindowSize(1366,768,0)
SetWindowAllowResize( 1 )

// set display properties
SetOrientationAllowed(0,0,1,0)
SetSyncRate(0,0)
SetVSync(1)
SetScissor(0,0,0,0)
UseNewDefaultFonts( 1 )
SetPrintSize(2.5)

coredrv$=""
global ServerListName$ as string
ServerListName$="NAT-PunchThrough-Server"
coredrv$=GetDocumentsPath()
coredrvc$="\"+ServerListName$
s=MakeFolder("raw:"+coredrv$+coredrvc$)   ` always attempts to create the folder, just returns 0 if failed
coredrv$="raw:"+coredrv$+coredrvc$+"\"

rem to write data out to log file or not
LogFile=0  ` switch to 1 here or using a text file below to activate
if GetFileExists(coredrv$+"savelogfile.txt")=1
    LogFile=1  ` to write events out to log file
endif

rem this program uses a default cpulevel that is very low to run in the background with low CPU useage
cpulevel=90  ` updated to apply CPU wait level up to 90 for around 10 FPS

rem to store server names
dim ServerName$[1000]

rem to store host IP and port values
dim ServerIP$[1000]
dim ServerPort[1000]
dim ServerLocalIP$[1000]
dim ServerLocalPort[1000]  ` optional to retrieve detected port, best to use a known fixed port value
dim ServerTime#[1000]  ` wait time before clearing the entry
ServerCap=0
ServerTotal=1000

rem stored IP address and ports of each client looking for servers, up to 1000 at a time
dim ClientName$[1000]
dim ClientIP$[1000]
dim ClientPort[1000]  ` optional to retrieve reported port, best to use a known fixed port value
dim ClientTime#[1000]  ` wait time before clearing the entry
ClientCap=0

rem list request arrays, can handle up to 25 at a time
dim ServerListIP$[25]
dim ServerListPort[25]
dim SendServerList[25]

SetCameraPosition(1,0,0,0)
SetCameraRotation(1,0,0,0)

ntconnect=0

Sync()

tmm=(timer()*1000)

rem setup
rem the port value below must be open and forwarded for the system running this listing program so that players can connect to it
ServerListUDPPort=18889  ` use a dedicated port for the game listing server to keep a separate port reserved for clients to communicate with each other
MultiIDUDP=CreateUDPListener("anyip4",ServerListUDPPort)

rem this port is for host and joining players to exchange data on
UDPPort=18890


mpmain:
earlytmm=(timer()*1000)

Print("FPS: "+str(ScreenFPS()))
Print("Listening...")

Print("---- Server List ----")

rem if in active rendering mode, show current list of servers and clients
rem add scrolling at some point so more than the screen length can be used
if ServerCap>0
    ss=0
    for i = 1 to ServerCap
    rem count down timer and remove from list if entry expires
    ServerTime#[i]=ServerTime#[i]-(1.0*fradjust#)
    if ServerTime#[i]<=0 and ss=0
        if i<ServerCap
            for ii = i to ServerCap-1
            ServerName$[ii]=ServerName$[ii+1]
            ServerIP$[ii]=ServerIP$[ii+1]
            ServerPort[ii]=ServerPort[ii+1]
            next ii
            
            ss=ss+1
        else
            ss=ss+1
        endif
        
        ServerTime#[i]=0
    endif
    
    Print(ServerName$[i]+": IP="+ServerIP$[i])
    next i
    
    if ss>0
        ServerCap=ServerCap-ss
        if ServerCap<0 then ServerCap=0
    endif
endif

Print("---- Client List ----")

if ClientCap>0
    ss=0
    for i = 1 to ClientCap
    rem count down timer and remove from list if entry expires
    ClientTime#[i]=ClientTime#[i]-(1.0*fradjust#)
    if ClientTime#[i]<=0 and ss=0
        if i<ClientCap
            for ii = i to ClientCap-1
            ClientName$[ii]=ClientName$[ii+1]
            ClientIP$[ii]=ClientIP$[ii+1]
            ClientPort[ii]=ClientPort[ii+1]
            next ii
            
            ss=ss+1
        else
            ss=ss+1
        endif
        
        ClientTime#[i]=0
    endif
        
    Print(ClientName$[i]+": "+ClientIP$[i])
    next i
    
    if ss>0
        ClientCap=ClientCap-ss
        if ClientCap<0 then ClientCap=0
    endif
endif


    repeat
        rem listen for messages from clients and hosts
        RecvPacket=GetUDPNetworkMessage(MultiIDUDP)  ` to retrieve UDP messages
        
        if RecvPacket>0
            ` UDP
            rem also retrieve the packet's port if UDP (only works with UDP packets), this is the external IP and port for the host/client as the server sees it
            PacketIP$=GetNetworkMessageFromIP(RecvPacket)
            PacketPort=GetNetworkMessageFromPort(RecvPacket)
            
            rem process received packets here
            pc$=GetNetworkMessageString(RecvPacket)
            
            rem server status packets, resets timer for this server
            rem some of this information is redundant/unnecessary, but is included in case a developer wants to analyze parameters and/or try different options
            if pc$="+Server"
                RecvName$=GetNetworkMessageString(RecvPacket)  ` name of server
                LocalHostIP$=GetNetworkMessageString(RecvPacket)  ` local IP address of server/host as submitted by server
                RecvIP$=PacketIP$  ` IP address of server as detected by this program
                LocalHostPort=GetNetworkMessageInteger(RecvPacket)  ` local port of server/host (not really needed)
                RecvPort=PacketPort
                
                rem add server to master list if it isn't already present
                s=0
                if ServerCap>0 and ServerCap<ServerTotal
                    for i = 1 to ServerCap
                    if RecvName$=ServerName$[i] and RecvIP$=ServerIP$[i] and RecvPort=ServerPort[i]
                        rem reset timer for this server listing so it remains on the list
                        ServerTime#[i]=1000
                        s=1
                    endif
                    next i
                endif
                
                rem if server is not yet listed, add it
                if s=0
                    ServerCap=ServerCap+1
                    ServerName$[ServerCap]=RecvName$
                    ServerLocalIP$[ServerCap]=LocalHostIP$  ` not really needed to establish connection
                    ServerLocalPort[ServerCap]=LocalHostPort  ` not really needed to establish connection
                    ServerIP$[ServerCap]=RecvIP$
                    ServerPort[ServerCap]=RecvPort
                    ServerTime#[ServerCap]=1000
        
                    rem if the server is a new listing, write out event to logfile
                    if LogFile>0
                        if GetFileExists(coredrv$+"logfile.txt")=0
                            OpenToWrite(1,coredrv$+"logfile.txt")
                        else
                            OpenToWrite(1,coredrv$+"logfile.txt",1)
                        endif
                        
                        s$="Server: "+RecvName$+" /Local IP="+LocalHostIP$+":"+str(LocalHostPort)+" / Public IP="+RecvIP$+":"+str(RecvPort)+" / "+GetCurrentDate()+", "+GetCurrentTime()
                    
                        WriteLine(1,s$)
                        CloseFile(1)
                    endif
                endif
            endif
            
            rem client connect to host request packets, when they try to join a particular hosted session
            if pc$="+Client"
                rem retrieve client information
                rem some of this information is redundant/unnecessary, but is included in case a developer wants to analyze parameters and/or try different options
                RecvName$=GetNetworkMessageString(RecvPacket)  ` name of client trying to connect
                RecvIP$=GetNetworkMessageString(RecvPacket)  ` IP address of the server they are trying to connect to (not the client, which is retrieved above with PacketIP$)
                RecvPort=GetNetworkMessageInteger(RecvPacket)  ` port of the server they are trying to connect to
                ClientLocalIP$=GetNetworkMessageString(RecvPacket)  ` local IP address of the client
                ClientLocalPort=GetNetworkMessageInteger(RecvPacket)  ` local port of the client
                
                rem rebroadcast client's data to host so the host can try to communicate directly back to them to communicate through NAT/Router/Firewall
                rem some of this information is redundant/unnecessary, but is included in case a developer wants to analyze parameters and/or try different options
                SendPacket=CreateNetworkMessage()
                AddNetworkMessageString(SendPacket,"+CLIENTCONNECT")
                AddNetworkMessageString(SendPacket,RecvName$)  ` send name of client trying to connect
                AddNetworkMessageString(SendPacket,ClientLocalIP$)  ` send local IP address of client trying to connect
                AddNetworkMessageInteger(SendPacket,ClientLocalPort)  ` send local port of client trying to connect
                AddNetworkMessageString(SendPacket,PacketIP$)  ` send external/public IP address of client trying to connect
                AddNetworkMessageInteger(SendPacket,PacketPort)  ` send external/public port of client trying to connect
                SendUDPNetworkMessage(MultiIDUDP,SendPacket,RecvIP$,ServerListUDPPort)  ` send client connection request to the host they are trying to connect to
                
                rem add client to master list if it isn't already present
                s=0
                if ClientCap>0
                    for i = 1 to ClientCap
                    if RecvName$=ClientName$[i] and PacketIP$=ClientIP$[i] and PacketPort=ClientPort[i]  ` only use the external/public port of the client
                        rem reset timer for this Client listing so it remains on the list
                        ClientTime#[i]=90  ` only hold for about 3 seconds
                        s=1
                    endif
                    next i
                endif
                
                rem if client is not yet listed, add it
                if s=0
                    ClientCap=ClientCap+1
                    ClientName$[ClientCap]=RecvName$
                    ClientIP$[ClientCap]=PacketIP$
                    ` ClientPort[ClientCap]=PacketPort  ` only use the external/public port of the client
                    ClientPort[ClientCap]=UDPPort
                    ClientTime#[i]=90
        
                    rem if the server is a new listing, write out event to logfile
                    if LogFile=1
                        if GetFileExists(coredrv$+"logfile.txt")=0
                            OpenToWrite(1,coredrv$+"logfile.txt")
                        else
                            OpenToWrite(1,coredrv$+"logfile.txt",1)
                        endif
                        
                        ` s$="Client: "+RecvName$+" / "+PacketIP$+" / "+str(RecvPortB)+" / To Server: "+RecvIP$+" / "+str(RecvPort)+" / "+GetCurrentDate()+", "+GetCurrentTime()
                        s$="Client: "+RecvName$+" / Local IP="+ClientLocalIP$+":"+str(ClientLocalPort)+" / Public IP="+PacketIP$+":"+str(PacketPort)+" / To Server: "+RecvIP$+":"+str(RecvPort)+" / "+GetCurrentDate()+", "+GetCurrentTime()
                    
                        WriteLine(1,s$)
                        CloseFile(1)
                    endif
                endif
            endif
            
            rem when client requests a list of available hosts
            if pc$="+List"
                rem find an available index
                s=0:ss=-1
                repeat
                    if SendServerList[s]=0
                        ss=s
                    endif
                    
                    s=s+1
                    if s>25 then ss=0
                until ss=>0
                
                ServerListIP$[ss]=PacketIP$
                ` ServerListPort[ss]=PacketPort  ` optional, in case the port is changed for the client requesting the list
                ServerListPort[ss]=ServerListUDPPort  ` send back on the server list port
                SendServerList[ss]=1
            endif
            
            DeleteNetworkMessage(RecvPacket)
        endif
    
    until RecvPacket<1
    

rem send list of hosts (ie game servers) to any player that requested it
for i = 0 to 25
if SendServerList[i]>0
    if SendServerList[i]<=ServerCap
        rem some of this information is redundant/unnecessary, but is included in case a developer wants to analyze parameters and/or try different options
        SendPacket=CreateNetworkMessage()
        AddNetworkMessageString(SendPacket,"+SERVERS")
        AddNetworkMessageInteger(SendPacket,SendServerList[i])  ` list position for server
        AddNetworkMessageString(SendPacket,ServerName$[SendServerList[i]])
        AddNetworkMessageString(SendPacket,ServerLocalIP$[SendServerList[i]])
        AddNetworkMessageInteger(SendPacket,ServerLocalPort[SendServerList[i]])
        AddNetworkMessageString(SendPacket,ServerIP$[SendServerList[i]])
        AddNetworkMessageInteger(SendPacket,ServerPort[SendServerList[i]])
        SendUDPNetworkMessage(MultiIDUDP,SendPacket,ServerListIP$[i],ServerListPort[i])
        
        SendServerList[i]=SendServerList[i]+1  ` one listing at a time to only broadcast active server listings
    else
        rem send final packet to instruct listening player(s) to stop listening
        SendPacket=CreateNetworkMessage()
        AddNetworkMessageString(SendPacket,"+SERVERSDONE")
        SendUDPNetworkMessage(MultiIDUDP,SendPacket,ServerListIP$[i],ServerListPort[i])
        
        SendServerList[i]=0
    endif
endif
next i


Sleep(cpulevel)

if RenderMode=0 then Sync()

if RenderMode=1
    Render2DFront()
    SetRenderToScreen()
    Render3D()
    ` Render2DFront()
    Swap()
endif


if GetRawKeyState(27)>0
    end
endif


gosub SetFrameTMM

goto mpmain



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




