
//  oc_pet.lsl
//
//  Copyright (c) 2004 - 2017 Francis Chung, Ilse Mannonen, Nandana Singh,
//  Cleo Collins, Satomi Ahn, Joy Stipe, Wendy Starfall, Garvin Twine,
//  littlemousy, Romka Swallowtail, Sumi Perl et al.
//
//  This script is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published
//  by the Free Software Foundation, version 2.
//
//  This script is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this script; if not, see www.gnu.org/licenses/gpl-2.0
//

// Debug(string sStr) { llOwnerSay("Debug ["+llGetScriptName()+"]: " + sStr); }

integer g_iBuild = 6;

list g_lMenuIDs;
integer g_iMenuStride = 3;

integer g_iAnimTimeout;
integer g_iPermissionTimeout;

key g_kWearer;

list g_lAnimSettings = ["~good","~pet","0.55","_PARTNER_ pets _SELF_'s head."];
float g_fRange = 10.0;

float g_fWalkingDistance = 1.0;
float g_fWalkingTau = 1.5;
float g_fAlignTau = 0.05;
float g_fAlignDelay = 0.6;

key g_kCmdGiver;
integer g_iCmdAuth;
key g_kPartner;
string g_sPartnerName;
float g_fTimeOut = 20.0;
string g_sDeviceName;

integer g_iTargetID;
string g_sSubAnim = "~pet";
string g_sDomAnim = "~good";
integer g_iVerbose = TRUE;


integer CMD_OWNER = 500;
integer CMD_WEARER = 503;

integer NOTIFY = 1002;
integer SAY = 1004;
integer LOADPIN = -1904;
integer REBOOT = -1000;
integer LINK_DIALOG = 3;
integer LINK_RLV  = 4;
integer LINK_SAVE = 5;
integer LINK_UPDATE = -10;
integer LM_SETTING_SAVE = 2000;
integer LM_SETTING_RESPONSE = 2002;
integer LM_SETTING_DELETE = 2003;

integer RLV_CMD = 6000;

integer ANIM_START = 7000;
integer ANIM_STOP = 7001;

integer DIALOG = -9000;
integer DIALOG_RESPONSE = -9001;
integer DIALOG_TIMEOUT = -9002;
integer SENSORDIALOG = -9003;
integer BUILD_REQUEST = 17760501;

string g_sSettingToken = "coupleanim_";
string g_sGlobalToken = "global_";
string g_sStopString = "stop";
integer g_iStopChan = 99;
integer g_iLMChannel = -8888;
integer g_iListener;

Dialog(key kRCPT, string sPrompt, list lButtons, list lUtilityButtons, integer iPage, integer iAuth, string sMenuID) {
    key kMenuID = llGenerateKey();
    string sSearch;
    if (sMenuID == "sensor") {
        if (llGetListLength(lButtons)) sSearch = "`"+llList2String(lButtons,0)+"`1";
        llMessageLinked(LINK_DIALOG, SENSORDIALOG, (string)kRCPT +"|"+sPrompt+"|0|``"+(string)AGENT+"`"+(string)g_fRange+"`"+(string)PI+sSearch+"|"+llDumpList2String(lUtilityButtons, "`")+"|" + (string)iAuth, kMenuID);
    } else
        llMessageLinked(LINK_DIALOG, DIALOG, (string)kRCPT + "|" + sPrompt + "|" + (string)iPage + "|" + llDumpList2String(lButtons, "`") + "|" + llDumpList2String(lUtilityButtons, "`") + "|" + (string)iAuth, kMenuID);
    integer iIndex = llListFindList(g_lMenuIDs, [kRCPT]);
    if (~iIndex) g_lMenuIDs = llListReplaceList(g_lMenuIDs, [kRCPT, kMenuID, sMenuID], iIndex, iIndex + g_iMenuStride - 1);
    else g_lMenuIDs += [kRCPT, kMenuID, sMenuID];
}

refreshTimer(){
    integer timeNow = llGetUnixTime();
    if (g_iAnimTimeout <= timeNow && g_iAnimTimeout > 0){
        g_iAnimTimeout=0;
        StopAnims();
    } else if (g_iPermissionTimeout <= timeNow && g_iPermissionTimeout > 0){
        g_iPermissionTimeout=0;
        llListenRemove(g_iListener);
        g_kPartner = NULL_KEY;
    }
    integer nextTimeout=g_iAnimTimeout;
    if (g_iPermissionTimeout < g_iAnimTimeout && g_iPermissionTimeout > 0)
        nextTimeout = g_iPermissionTimeout;
    llSetTimerEvent(nextTimeout-timeNow);
}

StopAnims() {
    if (llGetInventoryType(g_sSubAnim) == INVENTORY_ANIMATION) llMessageLinked(LINK_THIS, ANIM_STOP, g_sSubAnim, "");
    if (llGetInventoryType(g_sDomAnim) == INVENTORY_ANIMATION) {
        if (llKey2Name(g_kPartner) != "") {
            if (llGetPermissions() & PERMISSION_TRIGGER_ANIMATION) llStopAnimation(g_sDomAnim);
            llRegionSayTo(g_kPartner,g_iLMChannel,(string)g_kPartner+"booton");
        }
    }
    g_sSubAnim = "";
    g_sDomAnim = "";
}

MoveToPartner() {
    list partnerDetails = llGetObjectDetails(g_kPartner, [OBJECT_POS, OBJECT_ROT]);
    vector partnerPos = llList2Vector(partnerDetails, 0);
    rotation partnerRot = llList2Rot(partnerDetails, 1);
    vector partnerEuler = llRot2Euler(partnerRot);
    llMessageLinked(LINK_RLV, RLV_CMD, "setrot:" + (string)(-PI_BY_TWO-partnerEuler.z) + "=force", NULL_KEY);
    g_iTargetID = llTarget(partnerPos, g_fWalkingDistance);
    llMoveToTarget(partnerPos, g_fWalkingTau);
}

GetPartnerPermission() {
    string sObjectName = llGetObjectName();
    llSetObjectName(g_sDeviceName);
    llRequestPermissions(g_kPartner, PERMISSION_TRIGGER_ANIMATION);
    llSetObjectName(sObjectName);
}

default {
    on_rez(integer iStart) {
        if (g_sSubAnim != "" && g_sDomAnim != "") {
             llSleep(1.0);
             StopAnims();
        }
        llResetScript();
    }

    state_entry() {
        if (llGetStartParameter()==825) llSetRemoteScriptAccessPin(0);
        g_kWearer = llGetOwner();
        g_sDeviceName = llList2String(llGetLinkPrimitiveParams(1,[PRIM_NAME]),0);
    }

    listen(integer iChannel, string sName, key kID, string sMessage) {
        llListenRemove(g_iListener);
        if (iChannel == g_iStopChan) StopAnims();
    }

    link_message(integer iSender, integer iNum, string sStr, key kID){
        if (iNum >= CMD_OWNER && iNum <= CMD_WEARER) {
            list lParams = llParseString2List(sStr, [" "], []);
            g_kCmdGiver = kID;
            g_iCmdAuth = iNum;
            string sCommand = llToLower(llList2String(lParams, 0));
            string sValue = llToLower(llList2String(lParams, 1));
            if (sCommand == "pet" || sStr == "menu Couples" || sStr == "couples") {
                if (sCommand != "pet") lParams = ["pet","me"];
                if (llGetListLength(lParams) > 1) {
                    string sTmpName = llDumpList2String(llList2List(lParams, 1, -1)," ");
                    Dialog(g_kCmdGiver,"\nChoose a partner:\n",[sTmpName],["CANCEL"],0,iNum,"sensor");
                } else {
                    if (kID == g_kWearer) {
                        llMessageLinked(LINK_DIALOG,NOTIFY,"0"+"\n\nYou didn't give the name of the person you want to animate. If you for example want to invite Wendy Starfall to pet you, the command would be:\n\n /%CHANNEL% %PREFIX% pet wen\n",g_kWearer);
                    } else {
                        g_kPartner = g_kCmdGiver;
                        g_sPartnerName = "secondlife:///app/agent/"+(string)g_kPartner+"/about";
                        StopAnims();
                        GetPartnerPermission();
                        llMessageLinked(LINK_DIALOG,NOTIFY,"0"+"Asking "+g_sPartnerName+" to pet you.",g_kWearer);
                    }
                }
            } else if (sCommand == "stop" && (sValue == "couples" || sValue == "pet")) StopAnims();
            else if (sCommand == "couples" && sValue == "verbose") {
                sValue = llToLower(llList2String(lParams, 2));
                if (sValue == "off"){
                    g_iVerbose = FALSE;
                    llMessageLinked(LINK_SAVE, LM_SETTING_SAVE, g_sSettingToken + "verbose=" + (string)g_iVerbose, "");
                } else if (sValue == "on") {
                    g_iVerbose = TRUE;
                    llMessageLinked(LINK_SAVE, LM_SETTING_DELETE, g_sSettingToken + "verbose", "");
                }
                llMessageLinked(LINK_DIALOG,NOTIFY,"0"+"Verbose for couple animations is now turned "+sValue+".",kID);
            }
        } else if (iNum == LM_SETTING_RESPONSE) {
            list lParams = llParseString2List(sStr, ["="], []);
            string sToken = llList2String(lParams, 0);
            string sValue = llList2String(lParams, 1);
            if(sToken == g_sSettingToken + "timeout")
                g_fTimeOut = (float)sValue;
            else if (sToken == g_sSettingToken + "verbose")
                g_iVerbose = (integer)sValue;
            else if (sToken == g_sGlobalToken+"DeviceName")
                g_sDeviceName = sValue;
        } else if (iNum == DIALOG_RESPONSE) {
            integer iMenuIndex = llListFindList(g_lMenuIDs, [kID]);
            if (~iMenuIndex) {
                list lMenuParams = llParseString2List(sStr, ["|"], []);
                string sMessage = llList2String(lMenuParams, 1);
                string sMenu=llList2String(g_lMenuIDs, iMenuIndex + 1);
                g_lMenuIDs = llDeleteSubList(g_lMenuIDs, iMenuIndex - 1, iMenuIndex - 2 + g_iMenuStride);
                if (sMenu == "sensor") {
                    if (sMessage == "CANCEL");
                    else {
                        g_kPartner = (key)sMessage;
                        g_sPartnerName = "secondlife:///app/agent/"+(string)g_kPartner+"/about";
                        StopAnims();
                        GetPartnerPermission();
                        llMessageLinked(LINK_DIALOG,NOTIFY,"0"+"Inviting "+ g_sPartnerName + " to a couples animation.",g_kWearer);
                        llMessageLinked(LINK_DIALOG,NOTIFY,"0"+"%WEARERNAME% invited you to a couples animation! Click [Yes] to accept.",g_kPartner);
                    }
                }
            }
        } else if (iNum == DIALOG_TIMEOUT) {
            integer iMenuIndex = llListFindList(g_lMenuIDs, [kID]);
            g_lMenuIDs = llDeleteSubList(g_lMenuIDs, iMenuIndex - 1, iMenuIndex +3);
        } else if (iNum == LOADPIN && sStr == llGetScriptName()) {
            integer iPin = (integer)llFrand(99999.0)+1;
            llSetRemoteScriptAccessPin(iPin);
            llMessageLinked(iSender, LOADPIN, (string)iPin+"@"+llGetScriptName(),llGetKey());
        } else if (iNum == LINK_UPDATE) {
            if (sStr == "LINK_DIALOG") LINK_DIALOG = iSender;
            else if (sStr == "LINK_RLV") LINK_RLV = iSender;
            else if (sStr == "LINK_SAVE") LINK_SAVE = iSender;
        } else if (iNum == BUILD_REQUEST)
            llMessageLinked(iSender,iNum+g_iBuild,llGetScriptName(),"");
        else if (iNum == REBOOT && sStr == "reboot") llResetScript();
    }
    
    not_at_target() {
        // OpenSim fix
        if (g_iTargetID==0) return;

        llTargetRemove(g_iTargetID);
        g_iTargetID = 0;
        MoveToPartner();
    }

    at_target(integer tiNum, vector targetpos, vector ourpos) {
        // OpenSim fix
        if (g_iTargetID==0) return;
        
        llTargetRemove(tiNum);
        g_iTargetID = 0;
        llStopMoveToTarget();
        float offset = 10.0;
        offset = (float)llList2String(g_lAnimSettings,2);
        list partnerDetails = llGetObjectDetails(g_kPartner, [OBJECT_POS, OBJECT_ROT]);
        vector partnerPos = llList2Vector(partnerDetails, 0);
        rotation partnerRot = llList2Rot(partnerDetails, 1);
        vector myPos = llList2Vector(llGetObjectDetails(llGetOwner(), [OBJECT_POS]), 0);
        vector target = partnerPos + (<1.0, 0.0, 0.0> * partnerRot * offset);
        target.z = myPos.z;
        llMoveToTarget(target, g_fAlignTau);
        llSleep(g_fAlignDelay);
        llStopMoveToTarget();
        g_sSubAnim = llList2String(g_lAnimSettings,0);
        g_sDomAnim = llList2String(g_lAnimSettings,1);
        llMessageLinked(LINK_THIS, ANIM_START, g_sSubAnim, "");
        llRegionSayTo(g_kPartner,g_iLMChannel,(string)g_kPartner+"bootoff");
        llStartAnimation(g_sDomAnim);
        g_iListener = llListen(g_iStopChan, "", g_kPartner, g_sStopString);
        llMessageLinked(LINK_DIALOG,NOTIFY,"0"+"If you would like to stop the animation early, say /" + (string)g_iStopChan + g_sStopString + " to stop.",g_kPartner);
        string sText = llList2String(g_lAnimSettings,3);
        if (sText != "" && g_iVerbose) {
            sText = osReplaceString(sText,"_PARTNER_",g_sPartnerName,-1,0);
            sText = osReplaceString(sText,"_SELF_","%WEARERNAME%",-1,0);
            llMessageLinked(LINK_DIALOG,SAY,"0"+sText,"");
        }
        if (g_fTimeOut > 0.0) {
            g_iAnimTimeout=llGetUnixTime()+(integer)g_fTimeOut;
            if (g_sSubAnim == "~good" && g_fTimeOut > 20.0) g_iAnimTimeout = llGetUnixTime()+20;
        } else if (g_sSubAnim == "~good") g_iAnimTimeout = llGetUnixTime()+20;
        else g_iAnimTimeout=0;
        refreshTimer();
    }
    
    timer() {
        refreshTimer();
    }

    run_time_permissions(integer perm) {
        if (perm & PERMISSION_TRIGGER_ANIMATION) {
            key kID = llGetPermissionsKey();
            if (kID == g_kPartner) {
                g_iPermissionTimeout=0;
                MoveToPartner();
            } else {
                llMessageLinked(LINK_DIALOG,NOTIFY,"1"+"Sorry, but the request timed out.",kID);
            }
        }
    }
}