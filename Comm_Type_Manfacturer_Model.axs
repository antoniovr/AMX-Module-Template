MODULE_NAME='Comm_Type_Manfacturer_Model' (dev     vdvDevice,
														 dev     dvDevice)

(*
	EARPRO 2019
	Type:
	Manufacturer:
	Model:
	Notes:
	
	Revision notes:
	- 1.0 Release
		* Initial version

*)



#include 'EarAPI'
#include 'SNAPI'

#warn '*** Comment this define statement if it´s an unidirectional communication and there is no feedback from the unit'
#DEFINE __BIDIRECTIONAL__
#warn '*** Comment this define statement if there is no pulling status'
#DEFINE __PULLING__

DEFINE_CONSTANT

	volatile integer _PORT_ALREADY_IN_USE 		 = 14
	volatile integer _SOCKET_ALREADY_LISTENING = 15

	volatile integer _TYPE_RS232 = 1
	volatile integer _TYPE_IP    = 2

	volatile long    _TLID = 1

	volatile integer _ST_FREE           = 1   // Free to send commands to the device
	volatile integer _ST_WAIT_RESPONSE  = 2   // Waiting for a response from a device to a command
	volatile integer _ST_WAIT_EXECUTION = 3   // Waiting for an aditional time to execute (when there is no feedback)
	volatile integer _ST_WAIT_STATUS    = 4   // Waiting for a response from a device to a pulling status

	volatile integer _BUFFER_LONG       = 64  // Response maximum size
	volatile integer _QUEUE_ITEM_LONG   = 32  // Command maximum size
	volatile integer _QUEUE_LONG        = 32  // Qeue size
	volatile integer _TIMEOUT           = 3   // Maximum response time to a command
	volatile integer _DEFAULT_TEXE      = 1   // Default execution time to a command
	volatile integer _TIME_POLL_STATUS  = 20  // Time between pulling commands

	#warn '*** Uncomment if we are controlling a projector'
	//volatile integer _TIME_WARMING = 300
	//volatile integer _TIME_COOLING = 300

	#warn '*** Add here the command list and the index constant'
	volatile integer _CMD_POWER_ON  = 1
	volatile integer _CMD_POWER_OFF = 2
	// Etc

	volatile char _COMMANDS[][32] = {'',
												''} // Etc

	#IF_DEFINED __PULLING__
	#warn '*** Add here the pulling command list'
		volatile char _PULLING[][32] = {'',
													''} // Etc
	#END_IF

DEFINE_TYPE

	structure _uStatus
	{
		integer bOn
		char	  sInputType[16]
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
		integer    		nHead
		integer    		nTail
		_uQueueCommand auCommands[_Queue_LONG]
		_uQueueCommand uLast
	}

DEFINE_VARIABLE

	volatile long 		lTimes[1] = 200 // Update feedback every .20 sec

	volatile integer  nModuleStatus = _ST_FREE
	volatile _uQueue  uQueue
	volatile char     sBuffer[_BUFFER_LONG]
	volatile integer  nPullingCount = 1

	#warn '*** Define here what type of control is, _TYPE_RS232 or _TYPE_IP'
	persistent integer nControlType = _TYPE_RS232

	#warn '*** If the control type is IP, define here the port of the device to control'
	persistent long nIpPort = 1234

	persistent char sIPAddress[16] = '192.168.1.1'
	persistent char sBaudRate[6] = '9600'

	volatile sinteger nHandler = -1
	persistent integer nDebugLevel = 1

	volatile _uStatus uStatus


DEFINE_START

	create_buffer dvDevice,sBuffer

	Timeline_Create(_TLID,lTimes,1,Timeline_Relative,Timeline_Repeat)


	define_function fnPower(integer bPower)
	{
		stack_var _uQueueCommand newCommand
		if(bPower) {newCommand.sData = "''"}
		else		  {newCommand.sData = "''"}
		
		fnQueuePush(newCommand)
	}

	define_function fnInput(char sType[],integer nInput)
	{
		stack_var _uQueueCommand newCommand
		newCommand.sData = "''"

		fnQueuePush(newCommand)
	}

	define_function fnSwitch(integer nIn,
									 integer nOut,
									 integer nLevel)
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
				if(nDebugLevel == 4) {fnDebug("itoa(dvDevice.number),': -> ',uCommandToSend.sData")}
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
		nHandler = ip_client_open(dvDevice.PORT,"sIPAddress",nIPPort,1)
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
		#warn 'inserte aquí feedback si fuera necesario'
	}

DEFINE_EVENT

	channel_event[vdvDevice,POWER]
	{
		on:
		{
			if([vdvDevice,POWER_FB]) {fnPower(false)}
			else							 {fnPower(true)}
		}
	}

	channel_event[vdvDevice,PIC_MUTE]
	{
		on:
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

	channel_event[vdvDevice,MENU_FUNC]
	{
		on:
		{
			off[vdvDevice,MENU_FUNC]
		}
	}

	channel_event[vdvDevice,MENU_UP]
	{
		on:
		{
			off[vdvDevice,MENU_UP]
		}
	}

	channel_event[vdvDevice,MENU_DN]
	{
		on:
		{
			off[vdvDevice,MENU_DN]
		}	
	}	

	channel_event[vdvDevice,MENU_LT]
	{
		on:
		{
			off[vdvDevice,MENU_LT]
		}
	}

	channel_event[vdvDevice,MENU_RT]
	{
		on:
		{
			off[vdvDevice,MENU_RT]
		}
	}


	channel_event[vdvDevice,PWR_ON]
	{
		on:
		{
			fnPower(true)
			off[vdvDevice,PWR_ON]
		}
	}

	channel_event[vdvDevice,PWR_OFF]
	{
		on:
		{
			fnPower(false)
			off[vdvDevice,PWR_OFF]
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
			local_var char sData[64]
			local_var char cCmd
			
			sData = data.text
			
			select
			{
				active(find_string(sData,'?DEBUG',1)):
				{
					fnDebug("'DEBUG-',itoa(nDebugLevel)")
				}
				active(find_string(sData,'DEBUG-',1)):
				{
					remove_string(sData,'DEBUG-',1)
					nDebugLevel = atoi("sData")
				}
				active(find_string(sData,'PROPERTY-IP_Address,',1)):
				{
					remove_string(sData,'PROPERTY-IP_Address,',1)
					if(length_string(sData))
					{
						sIPAddress = sData
						nHandler = -1
						nControlType = _TYPE_IP
					}
				}
				active(find_string(sData,'PROPERTY-Port,',1)):
				{
					remove_string(sData,'PROPERTY-Port,',1)
					if(length_string(sData))
					{
						nIpPort = atoi("sData")
						nHandler = -1
						nControlType = _TYPE_IP
					}
				}			
				active(find_string(sData,'PROPERTY-Baud_Rate,',1)):
				{
					remove_string(sData,'PROPERTY-Baud_Rate,',1)
					if(length_string(sData))
					{
						nHandler = 0
						sBaudRate = sData
						send_command dvDevice,"'SET BAUD ',sBaudRate,',N,8,1 485 DISABLE'"
						send_command dvDevice,'HSOFF'					
						nControlType = _TYPE_RS232
					}			
				}
				active(find_string(sData,'PASSTHRU-',1)):
				{
					stack_var _uQueueCommand newElement
					remove_string(sData,'PASSTHRU-',1)
					newElement.sData = sData
					fnQueuePush(newElement)
					//send_string dvDevice,"sData"
				}
				active(find_string(sData,'INPUT-',1)):
				{
					stack_var integer nComma
					stack_var char sType[32]
					stack_var integer nInput
					remove_string(sData,'INPUT-',1)
					nComma = find_string(sData,',',1)
					sType = get_buffer_string(sData,nComma-1)
					nInput = atoi("sData")
					fnInput(sType,nInput)
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
		}
		offline:
		{
			if(nControlType == _TYPE_IP)
			{
				nHandler = -1
			}
		}
		onerror:
		{
			if(nControlType == _TYPE_IP)
			{
				if(data.number != _PORT_ALREADY_IN_USE && data.number != _SOCKET_ALREADY_LISTENING)
				{
					nHandler = -1
				}
			}		
		}
		string:
		{
			if(nDebugLevel == 4) {fnDebug("itoa(dvDevice.number),': <- ',data.text")}
			fnProcessBuffer()
		}
	}

	timeline_event[_TLID]
	{
		if(nControlType == _TYPE_IP)
		{
			wait 50 'reconnect'
			{
				if(nHandler < 0)
				{
					fnConnect()
				}
			}		
		}
		
		fnMainLine()
		fnFeedback()
	}

(**********************************************************)
(********************   EARPRO 2019	   ********************)
(**********************************************************) 