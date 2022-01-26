#!/bin/bash

## Melcloud2Domoticz version 3.0.0
##  Created by albert[at]hakvoort[.]co
##   Updated by Giljam Val


## Debug mode to trace process
McDebug=On
#McDebug=Off

if [ "$McDebug" = On ] ; then echo 'DEBUG: Debug mode On';echo; fi
if [ "$McDebug" = On ] ; then echo 'DEBUG: Setting various variables';echo; fi


## Melcloud username/password
USERNAME=MelCloudUsername@domain.com
PASSWORD=MelCloudPassword

## Domoticz Server Settings
SERVERIP=127.0.0.1
PORT=8080

## Script folder without trailing slash
FOLDER=/home/pi/melcloud


## Input file devices (configure devices in this file)
# Default file is: $FOLDER/.mcdevices
#
# File instructions:
#
# Please note values are Case Sensitive!
# One device per line, fill all values seperated by dashes (#) 
#
# So:
# Read_Update_eXclude#General_2ndZone_HotWater_Cool#Name#Type#Default#IDX
#
# Value description:
#
# R ead: Read from MelCloud, write to Domoticz if changed
# U pdate: Read from Domoticz, write to MelCloud if changed
# e X clude: Ignore value (only retrieve value for Debug mode)
#
# G eneral: General device
# 2 ndZone: Will only be processed if device value HasZone2 is true
# H otWater: Will only be processed if device value HasHotWaterTank is true
# C ool: Will only be processed if device value CanCool is true
#
# Name: Name value of MelCloud (keep in sync with MelCloud values, names in Domoticz can be changed since IDX is used)
# Type: Type of device (Switch/Text/Temp/Power/SetPoint/Selector) 
# Default: Default value (feature not yet available)
# IDX: Domoticz IDX value of device

# Location of input file:
INPUT="$FOLDER/.mcdevices"

## Trailing sign in input file
IFS='#'

## Path
CAT=/bin/cat
CURL=/usr/bin/curl
JQ=/usr/bin/jq
PIDOF=/bin/pidof
GREP=/bin/grep
WC=/usr/bin/wc

#Globals
mc_data=""
dom_data=""
DHeatpumpActive=""
MOperationMode=""
MHasZone2=""
MCanHeat=""
MCanCool=""
MHasHotWaterTank=""
MCurrentEnergyConsumed=""
MCurrentEnergyProduced=""


#SEND2MELCLOUD switch for turning on/off MelCloud updates (which makes either MelCloud of Domoticz leading)
#Create a virtual switch "MelCloud update" and configure the IDX below to be able to turn it on or off from Domoticz.
IDXSEND2MELCLOUD="4106"



#### Some new variables for new features (work in progress)

#Test for general Multiplier for ie Watt to Kwh conversion
#mc_data1000=`echo "scale=0; $mc_data*1000" | bc`


#String variable to create the MelCloud update string (not ready yet)
mcString='"EffectiveFlags":281483566710825,"HCControlType":1,"DeviceID":'"$DEVICEID"',"DeviceType":1,"HasPendingCommand":true,"Offline":false,"Scene":null,"SceneOwner":null'




###########################################################################
#                   No changes are needed here below                      #
###########################################################################

## Start

echo "-----------------------"
echo "Melcloud2Domoticz 3.0.0"
echo "-----------------------"


## check if we are the only local instance
if [ "$McDebug" = On ] ; then echo 'DEBUG: Checking instance';echo; fi

if [[ "`$PIDOF -x $(basename $0) -o %PPID`" ]]; then
        echo "This script is already running with PID `$PIDOF -x $(basename $0) -o %PPID`"
        exit
fi

## Check required apps availability
if [ "$McDebug" = On ] ; then echo 'DEBUG: Checking apps/paths';echo; fi

if [ ! -f $JQ ]; then
        echo "jq package is missing, check https://stedolan.github.io/jq/ or for Debian/Ubuntu -> apt-get install jq"
        exit
fi
if [ ! -f $CURL ]; then
        echo "curl is missing, or wrong path"
        exit
fi
if [ ! -f $CAT ]; then
        echo "cat is missing, or wrong path"
        exit
fi
if [ ! -f $PIDOF ]; then
        echo "pidof is missing, or wrong path"
        exit
fi
if [ ! -f $GREP ]; then
        echo "grep is missing, or wrong path"
        exit
fi
if [ ! -f $WC ]; then
        echo "wc is missing, or wrong path"
        exit
fi


## Check if Domoticz is online
if [ "$McDebug" = On ] ; then echo 'DEBUG: Check whether Domoticz is running';echo; fi

CHECKDOMOTICZ=`$CURL --max-time 5 --connect-timeout 5 -s "http://$SERVERIP:$PORT/json.htm?type=command&param=getversion" | $JQ '.status' -r`

if [ "$CHECKDOMOTICZ" != "OK" ]; then
        echo "Domoticz unreachable at $SERVERIP:$PORT"
        exit
fi


## Read the SEND2MELCLOUD value from Domoticz

if [ "$McDebug" = On ] ; then echo 'DEBUG: Loading Send2MelCloud setting from Domoticz';echo; fi

SEND2MELCLOUD=`$CURL -s "http://$SERVERIP:$PORT/json.htm?type=devices&rid=$IDXSEND2MELCLOUD" | $JQ -r '.result[]."Data"'`

## Set update status default to off for debugging/testing
#SEND2MELCLOUD="Off"

echo "Parameter SEND2MELCLOUD is: $SEND2MELCLOUD"


# Value to keep track of an updated device to trigger MelCloud update command, always default 0, will be updated to 1 if a device is changed
MelCloudUpdate=0
  

## Login on MelCloud and get Session key
if [ "$McDebug" = On ] ; then echo 'DEBUG: Testing MelCloud login and get session key';echo; fi

$CURL -s -o $FOLDER/.session 'https://app.melcloud.com/Mitsubishi.Wifi.Client/Login/ClientLogin' \
-H 'Cookie: policyaccepted=true; gsScrollPos-189=' \
-H 'Origin: https://app.melcloud.com' \
-H 'Accept-Encoding: gzip, deflate, br' \
-H 'Accept-Language: nl-NL,nl;q=0.9,en-NL;q=0.8,en;q=0.7,en-US;q=0.6,de;q=0.5' \
-H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/71.0.3578.98 Safari/537.36' \
-H 'Content-Type: application/json; charset=UTF-8' \
-H 'Accept: application/json, text/javascript, */*; q=0.01' \
-H 'Referer: https://app.melcloud.com/' -H 'X-Requested-With: XMLHttpRequest' \
-H 'Connection: keep-alive' --data-binary '{"Email":'"\"$USERNAME\""',"Password":'"\"$PASSWORD\""',"Language":12,"AppVersion":"1.17.3.1","Persist":true,"CaptchaResponse":null}' --compressed ;

LOGINCHECK=`/bin/cat $FOLDER/.session | $JQ '.ErrorId'`

if [ $LOGINCHECK == "1" ]; then
        echo "----------------------------------"
        echo "|Wrong Melcloud login credentials|"
        echo "---------------------------------"
        exit
fi

SESSION=`cat $FOLDER/.session | $JQ '."LoginData"."ContextKey"' -r`

if [ "$McDebug" = On ] ; then echo Sessionkey: $SESSION;echo; fi


## Get Data for all Devices/Building IDs and write it to .deviceid
if [ "$McDebug" = On ] ; then echo 'DEBUG: Get data from MelCloud';echo; fi

$CURL -s -o $FOLDER/.deviceid 'https://app.melcloud.com/Mitsubishi.Wifi.Client/User/ListDevices' \
-H 'X-MitsContextKey: '"$SESSION"'' -H 'Accept-Encoding: gzip, deflate, br' \
-H 'Accept-Language: nl-NL,nl;q=0.9,en-NL;q=0.8,en;q=0.7,en-US;q=0.6,de;q=0.5' \
-H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/71.0.3578.98 Safari/537.36' \
-H 'Accept: application/json, text/javascript, */*; q=0.01' \
-H 'Referer: https://app.melcloud.com/' \
-H 'X-Requested-With: XMLHttpRequest' \
-H 'Cookie: policyaccepted=true; gsScrollPos-189=' \
-H 'Connection: keep-alive' --compressed


## Check if there are multiple units, this script is (currently) only for 1 unit.
if [ "$McDebug" = On ] ; then echo 'DEBUG: Check number of devices (only one device is currently supported)';echo; fi

CHECKUNITS=`cat $FOLDER/.deviceid | $JQ '.' -r | $GREP DeviceID | $WC -l`

if [ $CHECKUNITS -gt 2 ]; then
        echo "Multiple units found, this script cannot yet handle more then 1 unit.."
        exit
fi

DEVICEID=`cat $FOLDER/.deviceid | $JQ '.' -r | grep DeviceID | head -n1 | cut -d : -f2 | xargs | sed 's/.$//'`
BUILDINGID=`cat $FOLDER/.deviceid | $JQ '.' -r | grep BuildingID | head -n1 | cut -d : -f2 | xargs | sed 's/.$//'`

echo DeviceID=$DEVICEID
echo BuildingID=$BUILDINGID
echo

## Read and prepare data set (remove [] characters) and write it to .meldata
if [ "$McDebug" = On ] ; then echo 'DEBUG: Preparing dataset';echo; fi

fulldata=$( cat $FOLDER/.deviceid )
echo "${fulldata:1:${#fulldata}-2}" > $FOLDER/.meldata>&1

## Check if data output is fine
/bin/cat $FOLDER/.meldata | $JQ -e . >/dev/null 2>&1

if [ ${PIPESTATUS[1]} != 0 ]; then
        echo "Retrieved Data is not json compatible, something went wrong....Help...."
        exit
fi

if [ "$McDebug" = On ] ; then echo 'DEBUG: Data is fine, you can check it in file .meldata';echo; fi





###############
###### Functions which can be called during process:
###############

function get_mc_value() {
  # Read MelCloud value from .meldata file
  mc_data=`sudo /bin/cat  $FOLDER/.meldata | $JQ ".Structure.Devices[].Device.$mc_dev"`

#  if [ "$McDebug" = On ] ; then echo "MelCloud value of $mc_dev: $mc_data";echo;fi
echo "MelCloud value of $mc_dev: $mc_data"

}


function get_dom_value() {
  # Reserring dom_data value
  dom_data="N/A"

  # Get Domoticz value (if IDX is configured)
  if [ "$idx" != "0" ]
    then
       case $dev_type in

         Switch)
            dom_data=`$CURL -s "http://$SERVERIP:$PORT/json.htm?type=devices&rid=$idx" | $JQ -r '.result[]."Status"'`
            ;;

         SetPoint)
            dom_data=`$CURL -s "http://$SERVERIP:$PORT/json.htm?type=devices&rid=$idx" | $JQ -r '.result[]."SetPoint"'`
            ;;

         Temp)
            dom_data=`$CURL -s "http://$SERVERIP:$PORT/json.htm?type=devices&rid=$idx" | $JQ -r '.result[]."Temp"'`
            ;;

         Selector)
            dom_data=`$CURL -s "http://$SERVERIP:$PORT/json.htm?type=devices&rid=$idx" | $JQ -r '.result[]."Level"'`
            ;;

         Power)
            dom_data=`$CURL -s "http://$SERVERIP:$PORT/json.htm?type=devices&rid=$idx" | $JQ -r '.result[]."Usage"'` | sed 's/.....$//'
         # (SED to remove text (Watt))
            ;;

         Text)
            dom_data=`$CURL -s "http://$SERVERIP:$PORT/json.htm?type=devices&rid=$idx" | $JQ -r '.result[]."Data"'`
            ;;

         Percentage)
            dom_data=`$CURL -s "http://$SERVERIP:$PORT/json.htm?type=devices&rid=$idx" | $JQ -r '.result[]."Data"'` | sed 's/.$//'
         # (SED to remove %-sign)
            ;;

      esac

#      if [ "$McDebug" = On ] ; then echo "Domoticz value of $mc_dev: $dom_data";echo;fi
      echo "Domoticz value of $mc_dev: $dom_data"
   else
      echo "No Domoticz IDX set for $mc_dev"
   fi
}

function ZoneOperationModeToText() {
  # Specific function for ZoneOperationMode (translate values to text)

        if [ "$mc_data" == "0" ]; then
                mc_data_text="Heating-Thermostat"
                        mc_data_value=10
        fi

        if [ "$mc_data" == "1" ]; then
                mc_data_text="Heating-FlowTemp"
                        mc_data_value=20
        fi

        if [ "$mc_data" == "2" ]; then
                mc_data_text="Heating-WDC"
                        mc_data_value=30
        fi

        if [ "$mc_data" == "3" ]; then
                mc_data_text="Cooling-Thermostat"
                        mc_data_value=40
        fi

        if [ "$mc_data" == "4" ]; then
                        mc_data_text="Cooling-FlowTemp"
                        mc_data_value=50
        fi
    if [ "$McDebug" = On ] ; then echo "Status: $mc_data_text";echo;fi
    if [ "$McDebug" = On ] ; then echo "Value: $mc_data_value";echo;fi
}

function OperationModeToText() {
  # Specific function for OperationMode (translate values to text)

        if [ "$mc_data" == "0" ]; then
                mc_data_text="Off"
        fi

        if [ "$mc_data" == "1" ]; then
                mc_data_text="SWW"
        fi

        if [ "$mc_data" == "2" ]; then
                mc_data_text="Heating"
        fi

        if [ "$mc_data" == "3" ]; then
                mc_data_text="Cooling"
        fi

        if [ "$mc_data" == "4" ]; then
                mc_data_text="Defrost??"
        fi

        if [ "$mc_data" == "5" ]; then
                mc_data_text="Standby"
        fi

        if [ "$mc_data" == "6" ]; then
                mc_data_text="Legionella"
        fi
    if [ "$McDebug" = On ] ; then echo "Status: $mc_data_text";echo;fi
}


function UpdateHeatpumpActive() {
## Update Heatpump active switch (turns on when the heatpump is running, heating/cooling/defrosting and SWW)

DHeatpumpActive=`$CURL -s "http://$SERVERIP:$PORT/json.htm?type=devices&rid=$idx"`

        if [ $DHeatpumpActive == "Off" ] && [[ $OperationMode =~ [1-4,6] ]]; then
                        echo "DHeatpumpActive = off | OperationMode > 0 or 5"
                        $CURL -s "http://$SERVERIP:$PORT/json.htm?type=command&param=switchlight&idx=$idx&switchcmd=On" > /dev/null
                else
                        if [ $DHeatpumpActive == "On" ] && [[ $OperationMode =~ [0,5] ]]; then
                                echo "DHeatpumpActive = on | OperationMode = 0"
                                $CURL -s "http://$SERVERIP:$PORT/json.htm?type=command&param=switchlight&idx=$idx&switchcmd=Off" > /dev/null
                        fi
        fi
}


#################                                       ###################
#################  Start processing devices one by one  ###################
#################                                       ###################


if [ "$McDebug" = On ] ; then echo 'DEBUG: Starting processing .mcdevices file by looping through data';echo; fi


# Using while loop to process every device line by line
while read -r xru g2hc mc_dev dev_type dev_default idx
do
   if [ "$McDebug" = On ] ; then echo;echo "______________________________________________________________________________";echo; fi
   if [ "$McDebug" = On ] ; then echo "DEBUG: Line: $xru#$g2hc#$mc_dev#$dev_type#$dev_default#$idx";echo; fi
   if [ "$McDebug" = On ] ; then echo "DEBUG: Processing $mc_dev"; fi 


# Special handling for device HeatPumpPower (renaming value)
   if [ "$mc_dev" = "HeatPumpPower" ] ; then
     mc_dev="Power"
   fi


# Get the value from MelCloud data file (unless it's an empty line in .mcdevices)
   if [ "$mc_dev" != "" ] ; then
     get_mc_value
   fi

# Get the value from Domoticz (unless it's an empty line in .mcdevices)
   if [ "$mc_dev" != "" ] ; then
     get_dom_value
   fi



# Setting globals for some devices
case $mc_dev in

   OperationModeZone1 | OperationModeZone2)
    ZoneOperationModeToText
    ;;

   OperationMode)
    OperationModeToText
    MOperationMode="$mc_data_text"
    ;;
 
   HasZone2)
    MHasZone2="$mc_data"
    ;;

   CanHeat)
    MCanHeat="$mc_data"
    ;;

   CanCool)
    MCanCool="$mc_data"
    ;;

   HasHotWaterTank)
    MHasHotWaterTank="$mc_data"
    ;;

   CurrentEnergyConsumed)
    MCurrentEnergyConsumed="$mc_data"
    ;;

   CurrentEnergyProduced)
    MCurrentEnergyProduced="$mc_data"
   ;;

esac


# Determing cooling functionality
if [[ ( "$g2hc" == "C"  ||  "$g2hc" == "C2" ) && ( "$MCanCool" == "false" ) ]] ; then
         echo "Device has no cooling function or is disabled"
         continue
fi

# Determing 2 zone functionality
if [[ ( "$g2hc" == "2" || "$g2hc" == "C2" ) && ( "$MHasZone2" == "false" ) ]] ; then
         echo "2nd zone not set up"
         continue
fi


######
######  Start processing device lines
######

case $xru in

   X|x)
#   ## Ignoring those lines
    echo "Value $mc_dev ignored"
    ;;

   R|r)
#    ## Proces for reading data per type of value (read MelCloud and update Domoticz if changed)
     if [ "$McDebug" = On ] ; then echo "DEBUG: Comparing both values of $mc_dev and updating Domoticz if changed"; fi

   case $dev_type in

    Text)
#    ## Proces for text values
      if [ $mc_data != $dom_data ] ; then
         $CURL -s "http://$SERVERIP:$PORT/json.htm?type=command&param=udevice&idx=$idx&nvalue=0&svalue=$mc_data" > /dev/null
         if [ "$McDebug" = On ] ; then echo "DEBUG: Text value $mc_dev is updated in Domoticz"; fi
      else
         if [ "$McDebug" = On ] ; then echo "DEBUG: Text value $mc_dev is not changed, no updated for Domoticz"; fi
      fi
    ;;

    Switch)
#    ## Proces for switch values
      if  [[ $mc_data == 'true' || $mc_data == "1" ]] && [[ $dom_data == "Off" ]] ; then
         $CURL -s "http://$SERVERIP:$PORT/json.htm?type=command&param=switchlight&idx=$idx&switchcmd=On" > /dev/null
         if [ "$McDebug" = On ] ; then echo "DEBUG: Switch $mc_dev turned off in Domoticz"; fi
      else if  [[ $mc_data == "false" || $mc_data == "0" ]] && [[ $dom_data = "On" ]] ; then
              $CURL -s "http://$SERVERIP:$PORT/json.htm?type=command&param=switchlight&idx=$idx&switchcmd=Off" > /dev/null
              if [ "$McDebug" = On ] ; then echo "DEBUG: Switch $mc_dev turned on in Domoticz"; fi
           else
              if [ "$McDebug" = On ] ; then echo "DEBUG: Switch $mc_dev is not changed, no update for Domoticz"; fi
           fi
      fi
    ;;

    SetPoint)
#    ## Proces for SetPoint values

       # SetPoint not yet configured

       if [ "$McDebug" = On ] ; then echo "DEBUG: Value $mc_dev is a SetPoint, but Domoticz will be overwritten *Not build yet* since it's configured as R in .mcdevices"; fi
     ;;

    Temp)
#    ## Proces for temperature values
       if [ $mc_data != $dom_data ] ; then
          $CURL -s "http://$SERVERIP:$PORT/json.htm?type=command&param=udevice&idx=$idx&nvalue=0&svalue=$mc_data" > /dev/null
          if [ "$McDebug" = On ] ; then echo "DEBUG: Temperature value of $mc_dev updated to $mc_data in Domoticz"; fi
       else
          if [ "$McDebug" = On ] ; then echo "DEBUG: Temperature value of $mc_dev not changed, no update for Domoticz"; fi
       fi
    ;;

    Selector)
#    ## Proces for Selector values
       if [ "$McDebug" = On ] ; then echo "DEBUG: Value $mc_dev is a selector (not yet implemented)";echo; fi
    ;;

    Power)
#    ## Proces for power values
          if [ "$mc_dev" = "DailyHeatingEnergyConsumed" ] ; then
            echo "Operation mode is: $MOperationMode"
        # Voor koelen andere optelsom toevoegen

            echo "CurrentEnergyConsumed is: $MCurrentEnergyConsumed"  
            mc_data1000=`scale=0; echo "$mc_data*1000/1" | bc`
            echo "mc1000 is: $mc_data1000"

            if [ "$MOperationMode" = "Heating" ] ; then
               $CURL -s "http://$SERVERIP:$PORT/json.htm?type=command&param=udevice&idx=$idx&nvalue=0&svalue=$MCurrentEnergyConsumed;$mc_data1000" > /dev/null
               if [ "$McDebug" = On ] ; then echo "DEBUG: Power value (heating mode) of $mc_dev updated to $mc_data1000 in Domoticz"; fi
            else
               # Voor koelen andere nog optelsom toevoegen
               $CURL -s "http://$SERVERIP:$PORT/json.htm?type=command&param=udevice&idx=$idx&nvalue=0&svalue=0;$mc_data1000" > /dev/null
               if [ "$McDebug" = On ] ; then echo "DEBUG: Power value (cooling mode) of $mc_dev updated to $mc_data1000 in Domoticz"; fi
            fi
          else
             if [ "$McDebug" = On ] ; then echo "DEBUG: Power value of $mc_dev not changed, no update for Domoticz"; fi
          fi
     ;;

     Percentage)
#    ## Proces for Percentage values
       if [ $mc_data != $dom_data ] ; then
       $CURL -s "http://$SERVERIP:$PORT/json.htm?type=command&param=udevice&idx=$idx&nvalue=0&svalue=$mc_data" > /dev/null
       if [ "$McDebug" = On ] ; then echo "DEBUG: Percentage value of $mc_dev updated to $mc_data in Domoticz"; fi
       else
          if [ "$McDebug" = On ] ; then echo "DEBUG: Percentage value of $mc_dev not changed, no update for Domoticz"; fi
       fi
     ;;

    esac
    ;;


    U|u)
 #    ## Proces for updating data per type of value (read Domoticz and update MelCloud if changed)
 #  Feature not ready yet

      if [ "$SEND2MELCLOUD" != "On" ] ; then
         echo "SEND2MELCLOUD is not ready yet, MelCloud not updated"
         continue
      fi

#     ## loop for preparing update data MelCloud
      if [ "$McDebug" = On ] ; then echo "DEBUG: Updating data value $mc_dev";echo; fi


      case $dev_type in

       Text)
#      ## Proces for text values
         if [ "$McDebug" = On ] ; then echo "DEBUG: Value $mc_dev is Textdata, is for info only, cannot update";echo; fi
         # If device is changed and updated (added to mcString) update MelCloudUpdate=1
         # MelCloudUpdate=1
         ;;

       Switch)
#      ## Proces for switch values
         if [ "$McDebug" = On ] ; then echo "DEBUG: Value $mc_dev is a switch, update feature not yet implemented";echo; fi
         # If device is changed and updated (added to mcString) update MelCloudUpdate=1
         # MelCloudUpdate=1
         ;;

       SetPoint)
#      ## Proces for SetPoint values
         if [ "$McDebug" = On ] ; then echo "DEBUG: Value $mc_dev is a SetPoint, update feature not yet implemented";echo; fi
         # If device is changed and updated (added to mcString) update MelCloudUpdate=1
         # MelCloudUpdate=1
         ;;

       Temp)
#      ## Proces for temperature values
         if [ "$McDebug" = On ] ; then echo "DEBUG: Value $mc_dev is a temperature, is for info only, cannot update";echo; fi
         # If device is changed and updated (added to mcString) update MelCloudUpdate=1
         # MelCloudUpdate=1
         ;;

       Selector)
#      ## Proces for Selector values
         if [ "$McDebug" = On ] ; then echo "DEBUG: Value $mc_dev is a selector, update feature not yet implemented";echo; fi
         # If device is changed and updated (added to mcString) update MelCloudUpdate=1
         # MelCloudUpdate=1
         ;;

       Percentage)
#      ## Proces for Percentage values
         if [ "$McDebug" = On ] ; then echo "DEBUG: Value $mc_dev is a percentage, is for info only, cannot update";echo; fi
         # If device is changed and updated (added to mcString) update MelCloudUpdate=1
         # MelCloudUpdate=1
         ;;

      esac


#    ## Check value validity
     # Nog bedenken hoe

#    ## Expand MelCloud string
     mcString="$mcString,blabla"
     if [ "$McDebug" = On ] ; then echo "$mcString";echo; fi
     ;;

   *)
   echo "Ongeldige letter in .mcdevices, alleen X, R of U zijn geldige  opties"
   ;;

   esac
#
echo ""

done < "$INPUT"
 
unset IFS

#Only update MelCloud is there are updates
if [ "$MelCloudUpdate" == "1" ]; then

   ## Update MelCloud data
   if [ "$McDebug" = On ] ; then echo 'DEBUG: Starting update MelCloud';echo; fi

   $CURL -s -o $FOLDER/.send 'https://app.melcloud.com/Mitsubishi.Wifi.Client/Device/SetAtw' -H 'X-MitsContextKey: '"$SESSION"'' \
   -H 'Origin: https://app.melcloud.com' -H 'Accept-Encoding: gzip, deflate, br' \
   -H 'Accept-Language: nl-NL,nl;q=0.9,en-NL;q=0.8,en;q=0.7,en-US;q=0.6,de;q=0.5' \
   -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/71.0.3578.98 Safari/537.36' \
   -H 'Content-Type: application/json; charset=UTF-8' \
   -H 'Accept: application/json, text/javascript, */*; q=0.01' \
   -H 'Referer: https://app.melcloud.com/' \
   -H 'X-Requested-With: XMLHttpRequest' \
   -H 'Cookie: policyaccepted=true; gsScrollPos-2=0' \
   -H 'Connection: keep-alive' --data-binary '{$mcString}' --compressed

   if [ "$McDebug" = On ] ; then echo 'DEBUG: Results from MelCloud: (stored in file .send)';echo; fi

   cat $FOLDER/.send | jq '.'

fi

if [ "$McDebug" = On ] ; then echo 'DEBUG: Script is done';echo; fi


