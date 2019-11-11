(***********************************************************)
(*  FILE_LAST_MODIFIED_ON: 11/11/2019  AT: 13:15:37        *)
(***********************************************************)

MODULE_NAME='Type_Manfacturer_Model_COMM' (dev vdvDeviceToTranslate,
					   dev dvDevice)

(*
    Type:
    Manufacturer:
    Model:
    Notes:
    
    Revision notes:
    - 1.0 Release
	    * Initial version

*)

    #warn '*** Comment this define statement if it´s an unidirectional communication and there is no feedback from the unit'
    #DEFINE __BIDIRECTIONAL__
    #warn '*** Comment this define statement if there is no pulling status'
    #DEFINE __PULLING__

DEFINE_DEVICE

    vdvDevice = DYNAMIC_VIRTUAL_DEVICE

DEFINE_CONSTANT

    integer _PORT_ALREADY_IN_USE  = 14
    integer _SOCKET_ALREADY_LISTENING = 15

    integer _TYPE_RS232 = 1
    integer _TYPE_IP    = 2

    // Timeline parameters
    long    _TLID = 1
    long lTimes[] = {200} // Update feedback every .20 sec

    integer _ST_FREE           = 1   // Free to send commands to the device
    integer _ST_WAIT_RESPONSE  = 2   // Waiting for a response from a device to a command
    integer _ST_WAIT_EXECUTION = 3   // Waiting for an aditional time to execute (when there is no feedback)
    integer _ST_WAIT_STATUS    = 4   // Waiting for a response from a device to a pulling status

    integer _BUFFER_LONG       = 64  // Response maximum size
    integer _QUEUE_ITEM_LONG   = 32  // Command maximum size
    integer _QUEUE_LONG        = 32  // Qeue size
    integer _TIMEOUT           = 3   // Maximum response time to a command
    integer _DEFAULT_TEXE      = 1   // Default execution time to a command
    integer _TIME_POLL_STATUS  = 20  // Time between pulling commands

    #warn '*** Uncomment if we are controlling a projector'
    //integer _TIME_WARMING = 300
    //integer _TIME_COOLING = 300

    #warn '*** Add here the command list and the index constant'
    integer _CMD_POWER_ON  = 1
    integer _CMD_POWER_OFF = 2
    // Etc

    char _COMMANDS[][32] = {'',
				     ''} // Etc

    #IF_DEFINED __PULLING__
	#warn '*** Add here the pulling command list'
	char _PULLING[][32] = {'',
			       ''} // Etc
    #END_IF

    // Define the number of key/values you want to store
    integer TOTAL_KEY_COUNT = 5

DEFINE_TYPE

    structure _uStatus
    {
	integer bOn
	char	sInputType[16]
	integer nInputNumber
	    
	#warn '*** Uncomment if we are controlling a projector'	
	//integer bWarming
	//integer bCooling
    }

    structure _uQueueCommand
    {
	char    sData[_QUEUE_ITEM_LONG]
	integer nTexe // Time to wait after executing the command
    }

    structure _uQueue
    {
	integer nHead
	integer nTail
	_uQueueCommand auCommands[_Queue_LONG]
	_uQueueCommand uLast
    }

    #include 'CUSTOMAPI'
    #include 'SNAPI'
    #include 'KeyValue'

DEFINE_VARIABLE

    volatile integer  nModuleStatus = _ST_FREE
    volatile _uQueue  uQueue
    volatile char     sBuffer[_BUFFER_LONG]
    volatile integer  nPullingCount = 1

    #warn '*** Define here what type of control is, _TYPE_RS232 or _TYPE_IP'
    persistent integer nControlType = _TYPE_RS232

    #warn '*** If the control type is IP, define here the port of the device to control'
    persistent long nIpPort = 1234

    #warn '*** Define default values for these parameters'
    persistent char sIPAddress[16] = '192.168.1.1'
    persistent char sBaudRate[16] = '9600'

    persistent integer nDebugLevel = 1

    volatile _uStatus uStatus
    persistent _uKeys uKeys

DEFINE_START

    translate_device(vdvDeviceToTranslate,vdvDevice)
    create_buffer dvDevice,sBuffer

    timeline_create(_TLID,lTimes,1,TIMELINE_RELATIVE,TIMELINE_REPEAT)

    define_function fnPower(integer bPower)
    {
	stack_var _uQueueCommand newCommand
	if(bPower) {newCommand.sData = "''"}
	else	   {newCommand.sData = "''"}
	
	fnQueuePush(newCommand)
    }

    define_function fnInput(char sType[],integer nInput)
    {
	stack_var _uQueueCommand newCommand
	newCommand.sData = "''"
	
	fnInfo("'Input: ',sType,' Num: ',itoa(nInput)")
	
	fnQueuePush(newCommand)
    }

    define_function fnSwitch(integer nIn,integer nOut,integer nLevel)
    {
	stack_var _uQueueCommand newCommand
	newCommand.sData = "''"

	fnQueuePush(newCommand)
    }

    define_function fnMainLine()
    {
	local_var _uQueueCommand uCommandToSend

	(* Free to send the next command or ask for status *)
	if (nModuleStatus == _ST_FREE)
	{
	    if(fnQueuePop(uCommandToSend))
	    {
		cancel_wait 'wait poll status'
		
		(* Send the command *)
		if(nDebugLevel == 4) {fnInfo("'-->> ',uCommandToSend.sData")}
		send_string dvDevice,"uCommandToSend.sData"
		
		#IF_DEFINED __BIDIRECTIONAL__
		    nModuleStatus = _ST_WAIT_RESPONSE // Two ways communication
		#ELSE
		    nModuleStatus = _ST_WAIT_EXECUTION // One way communication
		#END_IF
		
		if([vdvDevice,SIMULATED_FB])
		{
		    sBuffer = "sBuffer,'OK',10,13"
		    wait 1 fnProcessBuffer()
		}
	    }
	    else // If there is no command to send, we start pulling the device...
	    {
		wait _TIME_POLL_STATUS 'wait poll status'
		{
		    #IF_DEFINED __PULLING__
			send_string dvDevice,"_PULLING[nPullingCount]"
			nPullingCount ++
			if(nPullingCount > max_length_array(_PULLING))
			{
			    nPullingCount = 1
			}
			nModuleStatus = _ST_WAIT_STATUS				
		    #END_IF
		}
	    }
	}

	#IF_DEFINED __BIDIRECTIONAL__
	    (* TWO WAYS COMMUNICATION: Timeout in case that we don´t get a response in time *)
	    if(nModuleStatus == _ST_WAIT_RESPONSE)  
	    {
		wait _TIMEOUT 'wait response'
		{
		    nModuleStatus = _ST_FREE
		}
	    }
	#ELSE
	    (*ONE WAY COMMUNICATION: We block the module until the dessigned time has passed*)
	    if(nModuleStatus == _ST_WAIT_EXECUTION) 
	    {
		if (uQueue.uLast.nTexe)
		{
		    wait uQueue.uLast.nTexe 'wait execution'
		    {
			nModuleStatus = _ST_FREE
		    }
		}
		else
		{
		    nModuleStatus = _ST_FREE
		}
	    }
	#END_IF

	(* Esperamos mientras llega la respuesta del proyector a una solicitud de estado *)
	if(nModuleStatus == _ST_WAIT_STATUS)
	{
	    wait _TIMEOUT 'wait response'
	    {
		nModuleStatus = _ST_FREE
	    }
	}
    }

    define_function fnProcessBuffer()
    {
	local_var sPacket[255]
	while (fnTakePacket(sPacket)) {fnProcessPacket(sPacket)}
    }

    define_function fnConnect()
    {
	ip_client_open(dvDevice.PORT,"sIPAddress",nIPPort,1)
    }

    define_function fnQueueClear()
    {
	uQueue.nHead = 1
	uQueue.nTail = 1
    }

    define_function integer fnQueuePush(_uQueueCommand uNewCommand)
    {
	local_var integer nHead
	
	nHead = uQueue.nHead
	uQueue.auCommands[nHead] = uNewCommand
	
	nHead ++
	if (nHead > max_length_array(uQueue.auCommands))
	{
		nHead = 1
	}
	uQueue.nHead = nHead
	
	return (uQueue.nHead != uQueue.nTail)
    }

    define_function integer fnQueuePop(_uQueueCommand uCommand)
    {
	local_var integer nTail
	stack_var integer bExtractOK
	
	bExtractOK = FALSE
	
	if (uQueue.nTail != uQueue.nHead)
	{
	    nTail = uQueue.nTail
	    uCommand = uQueue.auCommands[nTail]
	    
	    nTail ++
	    if(nTail > max_length_array(uQueue.auCommands)) 
	    {
		nTail = 1
	    }
	    
	    uQueue.nTail = nTail
	    uQueue.uLast = uCommand
	    bExtractOK = TRUE
	}
	
	return bExtractOK
    }


    define_function fnResetModule()
    {
	set_virtual_channel_count(vdvDevice,1024)
	set_virtual_level_count(vdvDevice,16)
	
	fnQueueClear()
	nModuleStatus = _ST_FREE 
	
	off[vdvDevice,POWER_FB]
	
	if(nControlType == _TYPE_RS232)
	{
	    send_command dvDevice,"'SET BAUD ',sBaudRate,',N,8,1 485 DISABLE'"
	    send_command dvDevice,'HSOFF'
	}
	if(nControlType == _TYPE_IP)
	{
	    off[dvDevice,DEVICE_COMMUNICATING]
	    //ip_client_close(dvDevice.PORT)
	}	
    }

    define_function integer fnTakePacket(char sPacket[])
    {
	stack_var integer r
	r = false
	#warn '*** Insert here the code to extract the command from sBuffer'
	
	return r (* It would return TRUE if successfuly took the command from the buffer. *)
    }

    define_function fnProcessPacket(char sPacket[])
    {
	#warn '*** Insert the code to interpret the answer'
	(*
	select
	{
	    active(find_string(sPacket,'something',1)):
	    {
	    
	    }
	}
	*)
	
	#warn '*** Depending on the answer, activate the feedback channels in the virtual device'
	
	(*
	[vdvDevice,	POWER_FB]
	[vdvDevice,LAMP_COOLING_FB]
	[vdvDevice,LAMP_WARMING_FB]
	[..]
	*)
	
	#warn '*** After reading the answer, free the module to keep going'
	cancel_wait 'wait response'
	nModuleStatus = _ST_FREE
    }

    define_function fnFeedback()
    {
	#warn '*** Insert feedback if neccessary'
    }

DEFINE_EVENT

    channel_event[vdvDevice,0]
    {
	on:
	{
	    switch(channel.channel)
	    {
		case POWER:
		{
		    if([vdvDevice,POWER_FB]) {fnPower(false)}
		    else	             {fnPower(true)}		
		}
		case PWR_ON:
		{
		    fnPower(true)
		}
		case PWR_OFF:
		{
		    fnPower(false)
		}
		case PIC_MUTE:
		{
		    if([vdvDevice,PIC_MUTE_FB]) 
		    {
			// Video unmute
		    }
		    else								 
		    {
			// Video mute
		    }
		    off[vdvDevice,PIC_MUTE]		
		}
		case PLAY: 	  {}
		case STOP: 	  {}
		case PAUSE:       {}
		case RECORD:      {}
		case REW: 	  {}
		case FFWD: 	  {}
		case SREV:  	  {}
		case SFWD: 	  {}
		case MENU_UP:	  {}
		case MENU_DN:	  {}
		case MENU_LT:	  {}
		case MENU_RT:	  {}
		case MENU_SELECT: {}
		case MENU_SETUP:  {}
		case MENU_ENTER:  {}
		case MENU_RETURN: {}
		
		// Videoconference
		case MENU_ACCEPT: {}
		case MENU_REJECT: {}
	    }
	    
	    off[channel.device,channel.channel]
	}
    }

    channel_event[vdvDevice,PIC_MUTE_ON]
    {
	on:
	{
	    // Video mute
	}
	off:
	{
	    // Video unmute
	}
    }

    data_event[vdvDevice]
    {
	online:
	{
	    fnResetModule()
	}
	command:
	{ 
	    stack_var char sCmd[DUET_MAX_CMD_LEN]
	    stack_var char sHeader[DUET_MAX_HDR_LEN]
	    stack_var char sParam[DUET_MAX_PARAM_LEN]
	    sCmd = data.text
	    sHeader = DuetParseCmdHeader(sCmd)
	    sParam = DuetParseCmdParam(sCmd)
	    
	    fnInfo("'sHeader: ',sHeader,' sParam: ',sParam")
	    
	    switch(sHeader)
	    {
		case '?DEBUG':
		{
		    fnInfo("'DEBUG-',itoa(nDebugLevel)")
		}
		case 'DEBUG':
		{
		    nDebugLevel = atoi("sParam")
		}
		case 'REINIT':
		{
		    fnResetModule()
		}
		case 'PROPERTY':
		{
		    switch(sParam)
		    {
			case 'IP_Address':
			{
			    sIPAddress = DuetParseCmdParam(sCmd)
			    nControlType = _TYPE_IP
			    fnInfo("'Setting IP Address to: ',sIPAddress")
			}
			case 'Port':
			{
			    stack_var char sPort[16]
			    sPort = DuetParseCmdParam(sCmd)
			    nIpPort = atoi(sPort)
			    nControlType = _TYPE_IP
			    fnInfo("'Setting IP port to: ',itoa(nIpPort)")
			}
			case 'Baud_Rate':
			{
			    sBaudRate = DuetParseCmdParam(sCmd)					
			    fnInfo("'Setting Baud Rate to: ',sBaudRate")
			    nControlType = _TYPE_RS232
			    fnResetModule()
			}
		    }
		}
		case 'INPUT':
		{
		    stack_var char sInput[4]
		    stack_var integer nInput
		    sInput = DuetParseCmdParam(sCmd)
		    nInput = atoi("sInput")
		    fnInput(sParam,nInput)
		}
		case 'PASSTHRU':
		{
		    stack_var _uQueueCommand newElement
		    newElement.sData = sParam
		    fnQueuePush(newElement)
		}
		default:
		{
		    if(find_string(sHeader,'CI',1)) // Switcher command
		    {
			stack_var char sInput[4]
			stack_var char sOutput[4]
			stack_var integer nInput
			stack_var integer nOutput
			sInput = remove_string(sHeader,'O',1)
			nInput = atoi(sInput)
			sOutput = sHeader
			nOutput = atoi(sOutput)
			fnInfo("'COMM sInput vale: ',sInput")
			fnInfo("'COMM sOutput vale: ',sOutput")
			fnSwitch(nInput,nOutput,0)
		    }
		}
	    }
	}
    }

    data_event[dvDevice]
    {
	online:
	{
	    if(nControlType == _TYPE_RS232)
	    {
		send_command dvDevice,"'SET BAUD ',sBaudRate,',N,8,1 485 DISABLE'"
		send_command dvDevice,'HSOFF'
	    }
	    else if(nControlType == _TYPE_IP)
	    {
		on[data.device,DEVICE_COMMUNICATING]
	    }
	}
	offline:
	{
	    if(nControlType == _TYPE_IP)
	    {
		off[data.device,DEVICE_COMMUNICATING]
	    }
	}
	onerror:
	{
	    if(nControlType == _TYPE_IP)
	    {
		if(data.number != _PORT_ALREADY_IN_USE && data.number != _SOCKET_ALREADY_LISTENING)
		{
		    off[data.device,DEVICE_COMMUNICATING]
		}
		
		if(nDebugLevel == 4)
		{
		    fnInfo("'-->> ',fnGetIPErrorDescription(data.number)")
		}
	    }		
	}
	string:
	{
	    if(nDebugLevel == 4) {fnInfo("'<<-- ',data.text")}
	    fnProcessBuffer()
	}
    }

    timeline_event[_TLID]
    {
	if(nControlType == _TYPE_IP)
	{
	    wait 50 'reconnect'
	    {
		if(![dvDevice,DEVICE_COMMUNICATING])
		{
		    fnConnect()
		}
	    }		
	}
	
	fnMainLine()
	fnFeedback()
    }

(***********************************************************)
(*		    	END OF PROGRAM			   *)
(***********************************************************) 