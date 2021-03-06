#!/bin/bash
#########################################################################################################
# Title: preUpgrade.sh
# Purpose: To automate the 12c Upgrade Process
# Author : Sharad Pendkar
#
# Modified On      Who               Purpose
# --------------   ----------------  -------------------------------------------------------------------
# 12-MAR-2015      Sharad Pendkar    Initial Version
# 04-AUG-2015	   Huzaifa Zainuddin Changes for OUTT/ Added PARFILE to be called for variables
#########################################################################################################
. ${WKDIR}/bin/11g_Env.sh


echo "ORACLE_HOME=${ORACLE_HOME}"
export PATH=$PATH:/usr/lib

usage ()
{
  echo "Usage : $0 $ORACLE_SID someone@domain.com"
  rm -f ${OPTION1} > /dev/null
  exit 1
}

#MB Verify if the directories are existing:
check_directory () {
if [ ! -d $1 ]; then
        UpdateLog "Directory [$1] not existing."
fi
}

check_file () {
if [ ! -f $1 ]; then
	UpdateLog "File [$1] not existing."
else
	UpdateLog "`ls -ltr $1`"
fi
}

#-------------------------------------------------------
# Verify Script Arguments
#-------------------------------------------------------
if [ "$#" -gt 2 ]
then
  usage
fi

case "$#" in
   1)
      ORA_SID=$1
      MAILID=`grep MAILID $PARFILE  | awk -F"=" '{print $2}'`
      ;;
   2)
      ORA_SID=$1
      MAILID=$2
      ;;
 #--------------------------------------------------
 #Remove all hard-coded values for ORA_SID and MAILID
 #Have user inputted arguments added to script
 #---------------------------------------------------
 	*)
      ORA_SID=`grep ORACLE_SID $PARFILE  | awk -F"=" '{print $2}'`
      MAILID=`grep MAILID $PARFILE  | awk -F"=" '{print $2}'`
       ;;
esac

#MB For the case statement, we might encounter some errors:
#1. Need to check if first parameter is an existing SID and second parameter is an email

if [ `uname -a | grep -c Linux` -ne 0 ]; then
        ORATAB=/etc/oratab
else
        ORATAB=/var/opt/oracle/oratab
fi

if [ `grep -c ${ORACLE_SID} ${ORATAB}` -eq 0 ]; then
        Updatelog "ORACLE_SID not found in oratab"
	rm ${OPTION1} > /dev/null
        exit 1
fi

# #--------------------------------------------------
# #This information should remain the same
# # --------------------------------------------------
HOSTNAME=`hostname`
TIMESTAMP=`date +%Y%m%d_%H%M%S`
ORATAB=/etc/oratab
#-------------------------------------------------------------------------------------------------------
#Suggestion: If possible have OLD_ORA_HOME, and NEW_ORA_HOME paths be obtained using grep or automated, 
#These values should not be hard-coded in script
#-------------------------------------------------------------------------------
OLD_ORA_HOME=`grep OLD_ORA_HOME $PARFILE  | awk -F"=" '{print $2}'`
NEW_ORA_HOME=`grep NEW_ORA_HOME $PARFILE  | awk -F"=" '{print $2}'`
LOGDIR=$WKDIR/logs/${ORA_SID}

#-----------------------------------------------------------------
#Other variables leaving untouched no need to include in PARFILE
#-----------------------------------------------------------------
PFILE=${LOGDIR}/backup/init${ORA_SID}.ora.${TIMESTAMP}
SRC_TNSNAMES=${OLD_ORA_HOME}/network/admin/tnsnames.ora
SRC_LISTENER=${OLD_ORA_HOME}/network/admin/listener.ora
SRC_SQLNET=${OLD_ORA_HOME}/network/admin/sqlnet.ora
SRC_PWD_FILE=${OLD_ORA_HOME}/dbs/orapw${ORA_SID}
DEST_TNSNAMES=${NEW_ORA_HOME}/network/admin/tnsnames.ora
DEST_LISTENER=${NEW_ORA_HOME}/network/admin/listener.ora
DEST_SQLNET=${NEW_ORA_HOME}/network/admin/sqlnet.ora
DEST_PWD_FILE=${NEW_ORA_HOME}/dbs/orapw${ORA_SID}
BACKUP_ORATAB=$LOGDIR/backup/${HOSTNAME}.${ORA_SID}.oratab.$TIMESTAMP
ACTIVITY_LOG=${LOGDIR}/pre/${HOSTNAME}.${ORA_SID}.activity.${TIMESTAMP}.log
ACTIVITY_TMP_LOG=${LOGDIR}/pre/${HOSTNAME}.${ORA_SID}.tmp.${TIMESTAMP}.log

UpdateLog ()
{
   msg="$1"
   echo "$msg" | tee -a $ACTIVITY_LOG
}
  
ExitAutoUpgrade()
{
   PreUpgradeCheckSummary
   echo " "
   echo "        !!!!!!!!!!   $1 Upgrade check FAILED  !!!!!!!!!!  Please take corrective action."
   echo " "
   SUBJECT="AutoUpgrade : FAILED : 12c Pre Upgrade Verification - ${ORA_SID}@${HOSTNAME}"


   echo "Pre Upgrade Verification - ${ORA_SID}@${HOSTNAME}  - AutoGenerated by AutoUpgrade" | mailx -s "$SUBJECT" -a $ACTIVITY_LOG $MAILID

   rm ${OPTION1} > /dev/null
   exit 1;
}

#------------------------------------------------------------------
# Create LOGDIR and subdirectories
#------------------------------------------------------------------
[ -d "$LOGDIR" ] || ( mkdir -p $LOGDIR $LOGDIR/pre $LOGDIR/post $LOGDIR/backup $LOGDIR/upgrade 2> /dev/null && UpdateLog "Created Log Directory - $LOGDIR " ) || ( UpdateLog "Unable to create Log Directory ...!!.  Using /tmp as log directory." && LOGDIR=/tmp )

#-----------------------------------------------------------------
# Bring up database
#-----------------------------------------------------------------
STARTDB=${LOGDIR}/pre/startdatabasetest.log
$ORACLE_HOME/bin/sqlplus -s "/as sysdba" <<EOF > /dev/null
WHENEVER SQLERROR EXIT SQL.SQLCODE
SELECT LOG_MODE||':'||FLASHBACK_ON FROM V\$DATABASE;
exit SQL.SQLCODE
EOF
if [ $? -ne 0 ]; then
	UpdateLog "Database is currently down. Now starting database..."
$ORACLE_HOME/bin/sqlplus -s "/as sysdba" <<EOF > ${STARTDB}
WHENEVER SQLERROR EXIT SQL.SQLCODE
startup ;
exit SQL.SQLCODE
EOF
	if [ $? -ne 0 ]; then
		UpdateLog "preUpgrade.sh failed. Error: `grep ORA- ${STARTDB} | head -1`"; exigt 1;
	else
		UpdateLog "Database is now up."
	fi
else
	UpdateLog "Database is currently up"
fi

backupFile () 
{
   src_file=$1
   dest_file=$2
   prev_copy=$3

   if [ -f $src_file ]; then
      [ -f $dest_file ] && cp -up $dest_file $prev_copy 2> /dev/null
      [ -f $dest_file ] && cp $src_file $dest_file 2>/dev/null && cp -p $src_file $dest_file 2>/dev/null || cp -up $src_file $dest_file 2>/dev/null
   else
      UpdateLog "The file $src_file does not exists!  Ignoring Copy of this File. !!!!!!!!!!!!!!!!!"
   fi
}

PreUpgradeCheckSummary()
{
UpdateLog "=========================================================================================="
UpdateLog " "
UpdateLog "               SUMMARY OF PRE-UPGRADE -  Please verify carefully steps Marked <--"
UpdateLog " "
UpdateLog "=========================================================================================="

UpdateLog "STEP  1. No Check/Action required."
UpdateLog "STEP  2. AutoUpgrade Script will take care automatically."
UpdateLog "STEP  3. No Check/Action required."
UpdateLog "STEP  4. Manual Intervention Require.  <--"
UpdateLog "STEP  5. No Check/Action required."
UpdateLog "STEP  6. No Check/Action required."
UpdateLog "STEP  7. AutoUpgrade Script will take care automatically."
UpdateLog "STEP  8. AutoUpgrade Script will take care automatically."
UpdateLog "STEP  9. Manual Intervention Require.  <--"
UpdateLog "STEP 10. Manual Intervention Require.  <--"
UpdateLog "STEP 11. AutoUpgrade Script will take care automatically."
UpdateLog "STEP 12. Manual Intervention Require.  <--"
UpdateLog "STEP 13. Manual Intervention Require.  <--"
UpdateLog "STEP 14. Manual Intervention Require.  <--"
UpdateLog "STEP 15. AutoUpgrade Script will take care automatically."
UpdateLog "STEP 16. Manual Intervention Require.  <--"
UpdateLog "STEP 17. No Check/Action required."
UpdateLog " "
UpdateLog "=========================================================================================="
}

PreUpgradeVerfiyActivityLog()
{
    ErrorCheck=`cat $ACTIVITY_LOG | grep '^NLS_NCHAR_CHARACTERSET' | grep 'NOT OK' | wc -l`
    if [ $ErrorCheck -eq 1 ]; then
      UpdateLog "STEP 4.  NLS_NCHAR_CHARACTERSET is not AL16UTF16"
      ExitAutoUpgrade
    fi

    ErrorCheck=`cat $ACTIVITY_LOG | grep -E '^Total Number of files need Media recovery|^Total Number of files in Backup mode' | grep 'NOT OK' | wc -l`
    if [ $ErrorCheck -ge 1 ]; then
      UpdateLog "STEP 9.  Check for files EITHER that need Media recovery OR in Backup Mode. "
      ExitAutoUpgrade
    fi

    ErrorCheck=`cat $ACTIVITY_LOG | grep '^System Invalid Object count' | grep 'NOT OK' | wc -l`
    if [ $ErrorCheck -eq 1 ]; then
      UpdateLog "STEP 10. Check for SYS objects that are INVALID"
      ExitAutoUpgrade
    fi

    ErrorCheck=`cat $ACTIVITY_LOG | grep '^Logical Corruption Count' | grep 'NOT OK' | wc -l`
    if [ $ErrorCheck -eq 1 ]; then
      UpdateLog "STEP 12. Check for Logical Corruption."
      ExitAutoUpgrade
    fi

    ErrorCheck=`cat $ACTIVITY_LOG | grep '^Standby Database Configuration' | grep 'NOT OK' | wc -l`
    if [ $ErrorCheck -eq 1 ]; then
      UpdateLog "STEP 13. Check for Standby Configuration."
      ExitAutoUpgrade
    fi

    ErrorCheck=`cat $ACTIVITY_LOG | grep "^AUD" | grep 'NOT OK' | wc -l`
    if [ $ErrorCheck -eq 1 ]; then
      UpdateLog "STEP 14. Check for AUD$ table."
      ExitAutoUpgrade
    fi

    ErrorCheck=`cat $ACTIVITY_LOG | grep "^Overall Component Status" | grep 'NOT OK' | wc -l`
    if [ $ErrorCheck -eq 1 ]; then
      UpdateLog "STEP 16. Check for Oracle Installed Components."
      ExitAutoUpgrade
    fi
}

copy_file () {
if [ -f $1 ]; then
	cp $1 $2
	if [ $? -ne 0 ]; then
		UpdateLog "Directory `dirname $2` is not existing"
	else
		UpdateLog "$1 copied to $2"
	fi
else
	UpdateLog "$1 is not existing"
fi
}

# Check oratab file and copy information from it
PreUpgradeOSfileCopy ()
{
#set -x
UpdateLog "Checking oratab entry  ..."

PREV_COPY_FILE=${LOGDIR}/backup/${HOSTNAME}.${ORA_SID}.tnsnames.$TIMESTAMP
UpdateLog "Copying tnsnames.ora  ..."
backupFile $SRC_TNSNAMES $DEST_TNSNAMES $PREV_COPY_FILE

PREV_COPY_FILE=${LOGDIR}/backup/${HOSTNAME}.${ORA_SID}.listener.$TIMESTAMP
UpdateLog "Copying listener.ora  ..."
backupFile $SRC_LISTENER $DEST_LISTENER $PREV_COPY_FILE

PREV_COPY_FILE=${LOGDIR}/backup/${HOSTNAME}.${ORA_SID}.sqlnet.$TIMESTAMP
UpdateLog "Copying sqlnet.ora  ..."
backupFile $SRC_SQLNET $DEST_SQLNET $PREV_COPY_FILE

PREV_COPY_FILE=${LOGDIR}/backup/${HOSTNAME}.${ORA_SID}.orapw.$TIMESTAMP
UpdateLog "Copying oraPWD${ORA_SID}  ..."
backupFile $SRC_PWD_FILE $DEST_PWD_FILE $PREV_COPY_FILE

UpdateLog "Backing up crontab  ..."
crontab -l > ${LOGDIR}/backup/${HOSTNAME}.${ORA_SID}.crontab.$TIMESTAMP

UpdateLog "Copying Pre-upgrade 12c Utility from Oracle 12c Home to 11gR2 home ..."
copy_file ${NEW_ORA_HOME}/rdbms/admin/preupgrd.sql ${OLD_ORA_HOME}/rdbms/admin/preupgrd.sql
#-------------------------------------------------------------------------------
# Added utluppkg and emremove scripts to be copied to OLD ORA HOME directory
# Preupgrd.sql calls utluppkg.sql for pre upgrade steps
#-------------------------------------------------------------------------------
copy_file ${NEW_ORA_HOME}/rdbms/admin/utluppkg.sql ${OLD_ORA_HOME}/rdbms/admin/utluppkg.sql
copy_file ${NEW_ORA_HOME}/rdbms/admin/emremove.sql ${OLD_ORA_HOME}/rdbms/admin/emremove.sql
copy_file ${PFILE} ${NEW_ORA_HOME}/dbs/init${ORA_SID}.ora
copy_file ${OLD_ORA_HOME}/dbs/spfile${ORA_SID}.ora ${NEW_ORA_HOME}/dbs/spfile${ORA_SID}.ora

UpdateLog " "
UpdateLog " "
UpdateLog "Verfiying OS files - Overall status of OS level activity"
UpdateLog " "
UpdateLog " "
UpdateLog "Source Files: "
UpdateLog "------------------------------------------------------------------------------------------------------------"
check_file $SRC_TNSNAMES
check_file $SRC_LISTENER
check_file $SRC_SQLNET
check_file $SRC_PWD_FILE

#[ -f $SRC_TNSNAMES ] && ls -ltr $SRC_TNSNAMES | awk '{ printf("%3s %2s %5s \t", $6, $7, $8) } { print $9 } '
#[ -f $SRC_LISTENER ] && ls -ltr $SRC_LISTENER | awk '{ printf("%3s %2s %5s \t", $6, $7, $8) } { print $9 } '
#[ -f $SRC_SQLNET   ] && ls -ltr $SRC_SQLNET   | awk '{ printf("%3s %2s %5s \t", $6, $7, $8) } { print $9 } '
#[ -f $SRC_PWD_FILE ] && ls -ltr $SRC_PWD_FILE | awk '{ printf("%3s %2s %5s \t", $6, $7, $8) } { print $9 } '
UpdateLog " "
UpdateLog " "
UpdateLog "Destination Files: "
UpdateLog "------------------------------------------------------------------------------------------------------------"
check_file $DEST_TNSNAMES
check_file $DEST_LISTENER
check_file $DEST_SQLNET  
check_file $DEST_PWD_FILE
#[ -f $DEST_TNSNAMES  ] && ls -ltr $DEST_TNSNAMES | awk '{ printf("%3s %2s %5s \t", $6, $7, $8) } { print $9 } '
#[ -f $DEST_LISTENER  ] && ls -ltr $DEST_LISTENER | awk '{ printf("%3s %2s %5s \t", $6, $7, $8) } { print $9 } '
#[ -f $DEST_SQLNET    ] && ls -ltr $DEST_SQLNET   | awk '{ printf("%3s %2s %5s \t", $6, $7, $8) } { print $9 } '
#[ -f $DEST_PWD_FILE  ] && ls -ltr $DEST_PWD_FILE | awk '{ printf("%3s %2s %5s \t", $6, $7, $8) } { print $9 } '
UpdateLog " "
UpdateLog " "
UpdateLog "Previous Copy Files: "
UpdateLog "------------------------------------------------------------------------------------------------------------"
#ls -ltr ${LOGDIR}/*${TIMESTAMP} | awk '{ printf("%3s %2s %5s \t", $6, $7, $8) } { print $9 } '
if [ `ls -l ${LOGDIR} | grep "${TIMESTAMP}$" | wc -l` -eq 0 ]; then
	UpdateLog "No files found."
else
	UpdateLog "ls -l ${LOGDIR}/*${TIMESTAMP}"
fi
UpdateLog " "
UpdateLog " "
UpdateLog "Verifying $ORATAB Entry ..."
UpdateLog " "
#UpdateLog "`whoami`@`hostname -s`:`pwd`> cat $ORATAB | grep $ORA_SID"
if [ `grep -c $ORA_SID $ORATAB` -ne 0 ]; then
	UpdateLog "$ORA_SID is existing in $ORATAB"
else
	UpdateLog "$ORA_SID is not existing in $ORATAB"
fi
#UpdateLog "`cat $ORATAB | grep $ORA_SID`"
UpdateLog " "
UpdateLog " "

}

#Captures the information and inputs it into log file
clear
UpdateLog "============================================================================== "
UpdateLog " "
UpdateLog "       HOSTNAME : ${HOSTNAME}"
UpdateLog "     Oracle SID : $ORA_SID"
UpdateLog "Old Oracle Home : ${OLD_ORA_HOME}"
UpdateLog "New Oracle Home : ${NEW_ORA_HOME}"
UpdateLog "        Log Dir : $LOGDIR"
UpdateLog "   Activity Log : $ACTIVITY_LOG"
UpdateLog "        Mail ID : $MAILID"
UpdateLog "         OPTION : Pre-Check"
UpdateLog " "
UpdateLog "============================================================================== "
UpdateLog " "
while true
do
   echo "Please confirm above inputs (Y/N) : "
   read ans
   case $ans in
     n|N)
	 rm ${OPTION1} > /dev/null
         exit 1
         ;;
     y|Y)
         break
         ;;
   esac
done

echo "Please confirm above inputs (Y/N) : " >> $ACTIVITY_LOG
UpdateLog "Your answer : $ans"

PreUpgradeOSfileCopy

UpdateLog " "
UpdateLog "Validating Input Values..." 
UpdateLog " "

if [ `cat $ORATAB | grep -v "^#" | grep "$ORA_SID" | wc -l` -ge 2 ]; then
   UpdateLog "Duplicate entry in $ORATAB file.  Needs manual intervention to correct it.  Quitting AutoUpgrade Script !!!!!!!!!!"
   ExitAutoUpgrade "INVALID Input"
elif [ `cat $ORATAB | grep -v "^#" | grep "$ORA_SID" | wc -l` -eq 1 ]; then
   OLD_ORA_HOME=`cat $ORATAB | grep -v "^#" | grep "$ORA_SID" | cut -d":" -f2`
else
   OLD_ORA_HOME=`cat $ORATAB | grep "^###AutoUpgradeScript###" | grep "$ORA_SID" | cut -d":" -f2`
   if [ -z "$OLD_ORA_HOME" ]; then
      UpdateLog "Old Oracle Home does not exists in $ORATAB file.  Quitting AutoUpgrade Script !!!!!!!!!!"
      ExitAutoUpgrade "INVALID Input"
   fi
fi

if [ ! -d "$NEW_ORA_HOME" ]; then
    UpdateLog "New Oracle home does not exists.  Quitting AutoUpgrade Script !!!!!!!!!!"
    rm ${OPTION1} > /dev/null
    exit 1
fi

export ORACLE_SID=$ORA_SID
export ORACLE_HOME=$OLD_ORA_HOME

if [ "$ORACLE_HOME" = "$NEW_ORA_HOME" ]; then
   OLD_ORA_HOME=`cat $ORATAB | grep "^###AutoUpgradeScript###" | grep "$ORA_SID" | cut -d":" -f2`
   export ORACLE_HOME=$OLD_ORA_HOME
fi

SCRIPT_FILE=$LOGDIR/pre/default_ts.${TIMESTAMP}.sql
SCRIPT_LOGFILE=$LOGDIR/pre/default_ts.${TIMESTAMP}.log

UpdateLog "Checking DB Connectivity with Old Oracle Home"
UpdateLog " "

#HZ Added error handling, pls verify if correct
$ORACLE_HOME/bin/sqlplus -s "/as sysdba" <<EOF > $SCRIPT_FILE
WHENEVER SQLERROR EXIT SQL.SQLCODE
set echo off head off feed off
create pfile='${PFILE}' from spfile;
select 'spool ${SCRIPT_LOGFILE}' || chr(10) || chr(13) || 'set echo on' || chr(10) || chr(13) || 'alter user '||username||' default tablespace SYSTEM;' || chr(10) || chr(13) || 'exit;' from dba_users where username in ('SYS', 'SYSTEM' ) and default_tablespace != 'SYSTEM';
exit SQL.SQLCODE
EOF
#MB i have updated the syntax here. there is no condition in the condition clause.
if [ $? -ne 0 ]; then
   UpdateLog "preUpgrade.sh failed. Error: `grep ORA- $SCRIPT_FILE | head -1`"
   rm ${OPTION1} > /dev/null
   exit 1
else
   UpdateLog "Connectivity with OLD Oracle Home verified."
fi

#MB Removed, not sure if what is this for
#[ -f $SCRIPT_FILE ] && [ `cat $SCRIPT_FILE | grep alter | wc -l` -eq 0 ] && rm $SCRIPT_FILE 2> /dev/null || sqlplus "/as sysdba" @$SCRIPT_FILE

UpdateLog "Input Values Validated by AutoUpgrade Script on `date` "
UpdateLog " "
UpdateLog " "
UpdateLog "------------------------------------------------------------------------------------------"
UpdateLog "Activity Log File: $ACTIVITY_LOG "
UpdateLog "------------------------------------------------------------------------------------------"
UpdateLog " "

sleep 5

#$ORACLE_HOME/bin/sqlplus "/as sysdba" @${WKDIR}/sql/preUpg.sql > $ACTIVITY_TMP_LOG

#preUpg.sql is run

$ORACLE_HOME/bin/sqlplus -s "/as sysdba" @${WKDIR}/sql/preUpg.sql ${LOGDIR} ${ORA_SID} ${TIMESTAMP} > $ACTIVITY_TMP_LOG
cat $ACTIVITY_TMP_LOG >> $ACTIVITY_LOG

#MB Commneted out for testing purposes
cat $ACTIVITY_LOG

PreUpgradeVerfiyActivityLog
#MB why is it needed to rerun PreUpgradeOSfileCopy?
if [ `cat $ACTIVITY_LOG | grep FAILED | wc -l` -eq 0 ]; then
   UpdateLog " "
   UpdateLog " PRE-Upgrade is Successful. "
   UpdateLog " "
   sleep 5
   UpdateLog "Starting updating OS files "
   PreUpgradeOSfileCopy
   UpdateLog " "
   UpdateLog " "
fi
PreUpgradeCheckSummary
UpdateLog " "
UpdateLog "------------------------------------------------------------------------------------------"
UpdateLog "Activity Log File: $ACTIVITY_LOG "
UpdateLog "------------------------------------------------------------------------------------------"
UpdateLog " "
UpdateLog "Please login to OLD oracle home and run the PRE-Upgrade tool provided by Oracle i.e. preupgrd.sql "
UpdateLog " "
UpdateLog "@?/rdbms/admin/preupgrd.sql"
UpdateLog " "
echo
echo
#Sending email notification
SUBJECT="AutoUpgrade : Status : 12c Pre Upgrade Verification - ${ORA_SID}@${HOSTNAME}"
if [ `whereis uuencode | cut -d' ' -f2 | grep -c "uuencode$"` -eq 0 ]; then
	echo "Pre Upgrade Verification - ${ORA_SID}@${HOSTNAME}  - AutoGenerated by AUTODB" | mailx -s "$SUBJECT" $MAILID
	echo "`date` notification email sent without attachment. uuencode is not installed"
else 
	echo "Pre Upgrade Verification - ${ORA_SID}@${HOSTNAME}  - AutoGenerated by AUTODB" | mailx -s "$SUBJECT" -a ${ACTIVITY_LOG} $MAILID 
	echo "`date` email notification sent  with attachment"
fi
