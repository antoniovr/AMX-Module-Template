MODULE_NAME='Type_Manufacturer_Model_Simple_COMM' (dev vdvDev,dev dvDevice)
(***********************************************************)
(*  FILE CREATED ON: 07/22/2019  AT: 09:13:31              *)
(***********************************************************)
(***********************************************************)
(*  FILE_LAST_MODIFIED_ON: 09/11/2019  AT: 09:54:20        *)
(***********************************************************)

#include 'SNAPI'
#include 'CUSTOMAPI'

DEFINE_DEVICE

    vdvDevice = DYNAMIC_VIRTUAL_DEVICE

(***********************************************************)
(*               CONSTANT DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_CONSTANT

    long _TLID = 1
    long lTimes[] = {30000}
    
    integer _TYPE_IP  = 1
    integer _TYPE_RS232 = 2

(***********************************************************)
(*               VARIABLE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_VARIABLE

    volatile integer nControlType = _TYPE_RS232
    
    persistent char sIPAddress[] = '192.168.1.100'
    volatile long lIPPort = 1234
    
    persistent char sBaudRate[] = '9600'
    
    
    persistent integer nDebugLevel = 1

(***********************************************************)
(*                STARTUP CODE GOES BELOW                  *)
(***********************************************************)
DEFINE_START

    translate_device(vdvDev,vdvDevice)
    timeline_create(_TLID,lTimes,1,TIMELINE_RELATIVE,TIMELINE_REPEAT)
    
    define_function fnResetModule()
    {
	set_virtual_channel_count(vdvDevice,1024)
	set_virtual_level_count(vdvDevice,16)    
	
	off[vdvDevice,POWER_FB]
	
	if(nControlType == _TYPE_RS232)
	{
	    send_command dvDevice,"'SET BAUD ',sBaudRate,',N,8,1 485 DISABLE'"
	    send_command dvDevice,'HSOFF'
	}
	else if(nControlType == _TYPE_IP)
	{
	    off[dvDevice,DEVICE_COMMUNICATING]
	}
    }
    
    define_function fnConnect()
    {
	ip_client_open(dvDevice.PORT,sIPAddress,lIPPort,IP_TCP)
    }
    
    define_function fnPower(integer bPower)
    {
	fnInfo("'fnPower(',itoa(bPower),')'")
    }
    
    define_function fnInput(char sType[],integer nNum)
    {
	fnInfo("'fnInput(',sType,',',itoa(nNum),')'")
    }

(***********************************************************)
(*                THE EVENTS GO BELOW                      *)
(***********************************************************)
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
		case MENU_FUNC:	{}
		case MENU_UP:	{}
		case MENU_DN:	{}
		case MENU_LT:	{}
		case MENU_RT:	{}
	    }
	    
	    off[channel.device,channel.channel]
	}
    }

    data_event[vdvDevice]
    {
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
			    lIpPort = atoi(sPort)
			    nControlType = _TYPE_IP
			    fnInfo("'Setting IP port to: ',itoa(lIpPort)")
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
		    send_string dvDevice,"DuetParseCmdParam(sCmd)"
		}
	    }
	}
    }

    data_event[dvDevice]
    {
	online:
	{
	    on[vdvDevice,DEVICE_COMMUNICATING]
	}
	offline:
	{
	    off[vdvDevice,DEVICE_COMMUNICATING]
	}
    }

    timeline_event[_TLID]
    {
	if(nControlType == _TYPE_IP && ![vdvDevice,DEVICE_COMMUNICATING])
	{
	    fnConnect()
	}
    }

(***********************************************************)
(*		    	END OF PROGRAM			   *)
(***********************************************************) 