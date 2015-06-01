#!/bin/env ksh

#################################################################################
####                                                                            #
##  Program name: move2nfs.ksh                                                  #
##                                                                              #
##  Description: script to move file from out/ folder to in folder on NFS       #
##              out/ - file from CDA pub server generated(ODS/DFS/TS/DTF)       #
##              /dataout/cda/send/<CDAInst>/stg/ -  file stag for CDA publisher
##              /dataout/cda/send/<CDAInst>/out/ -  file of CDA publisher
##                                                                              #
#################################################################################
## Revision History                                                     #########
#################################################################################
# Wei           v1.0    16 Dec 2014        Creation
# Wei           v1.1    18 Dec 2014        Change in/ & aud/ to stg/ method
# Wei           v1.2    16 Jan 2015        Add -p and -s parameter
#                                          to support primary and standby DFS
#                                          Like DDO DFS and RPM DFS
#
################################################################################

## Program PATH, Program Name
PP=$(dirname $0)
PN=$(basename "$0" ".ksh")

# -----------------------------------------------------------------------------
# Log functions
# -----------------------------------------------------------------------------

fn_log_info()  { echo "$(date '+%D %T'): $1" |tee -a ${LOGFILE}; }
fn_log_warn()  { echo "$(date '+%D %T'): [WARNING] $1"  | tee -a ${LOGFILE}; }
fn_log_error() { echo "$(date '+%D %T'): [ERROR] $1"  | tee -a ${LOGFILE}; }

fn_usage () {
        print "ERROR! Usage: ${0##*/} [CDA InstID] [File Out directory] [-p|-s]"
}
# -----------------------------------------------------------------------------
# Small utility functions for reducing code duplication
# ---------------

fn_log_rotate() {
        ## MAX LOG SIZE = 10MB
        MAX_LOG_SIZE=10240000
        if [ -f $1 ]; then
                LOG_SIZE=$(ls -l $1 |awk '{print $5}')
                if [ $LOG_SIZE -ge $MAX_LOG_SIZE ]; then
                        fn_log_info "Cutting off the file $1"
                        mv $1 $1.old || fn_log_warn "Moving file $1 failed"
                fi
        else
                fn_log_warn "$1 not found"
        fi
}

SENDDIR=/dataout/cda/send
LOGFILE=$PP/$PN.log
OUTFILE=$PP/$PN.txt
# -----------------------------------------------------------------------------
# Main Program
# -----------------------------------------------------------------------------

#

if [ $# -ne 3 ]; then
        fn_log_error "Wrong parameter with $PN "
        fn_usage
        exit 1
else
        INSTID=$1
        OUTDIR=$2
        PS_FLAG=$3
        CDASTG_DIR=$SENDDIR/$INSTID/stg
        if [ "$PS_FLAG" == "-p" ]; then
                CDAOUT_DIR=$SENDDIR/$INSTID/out
        elif [ "$PS_FLAG" == "-s" ]; then
                CDAOUT_DIR=$SENDDIR/$INSTID/sout
        else
                fn_log_error "The parameter would be -p or -s"
                fn_usage
                exit 1
        fi

        if [ ! -d $OUTDIR ]; then
                fn_log_error "$OUTDIR not found. exit"
                exit 2
        fi
        if [ ! -d $CDASTG_DIR ]; then
                fn_log_error "$CDASTG_DIR not found. exit"
                exit 2
        fi
        if [ ! -d $CDAOUT_DIR ]; then
                fn_log_error "$CDAOUT_DIR not found. exit"
                exit 2
        fi

        ## To Judge whether it has files in OUTDIR
        FILES=$(ls $OUTDIR)
        if [ ! -z "$FILES" ]; then
                ## Loging the FILE information
                fn_log_info " - " >> $OUTFILE
                ls -l $OUTDIR >> $OUTFILE
                ## Start to move the file from OUTDIR to STGDIR
                fn_log_info "Move $(ls $OUTDIR|wc -l) files from $OUTDIR to $CDASTG_DIR"
                mv $OUTDIR/* $CDASTG_DIR 2>> $LOGFILE
                fn_log_info "Move $(ls $CDASTG_DIR|wc -l) files from $CDASTG_DIR to $CDAOUT_DIR"
                mv $CDASTG_DIR/* $CDAOUT_DIR 2>>$LOGFILE
        fi
fi

[ -f $LOGFILE ] && fn_log_rotate $LOGFILE
exit 0
