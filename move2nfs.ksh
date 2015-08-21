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
# Wei           v1.3    1  Jun 2015        Add fn_out_rotate function
#                                          Control moving file No. let it smart
#                                          Set THRESHOLD value
#                                          When CDA backlog on cmp/ and out/, both are less THRESHOLD value,
#                                          Then move files(No.=THRESHOLD) from stg/ to out/
# Wei           v1.4    12 Jun 2015        Fix the error of fn_out_rotate and size => 100MB
#                                          Support multi CDA instances
# Wei           v1.5    13 Jun 2015        Separate move2stg and move2out
#
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

fn_out_rotate() {
        ## MAX OUT SIZE = 100MB
        MAX_OUT_SIZE=102400000
        if [ -f $1 ]; then
                OUT_SIZE=$(ls -l $1 |awk '{print $5}')
                if [ $OUT_SIZE -ge $MAX_OUT_SIZE ]; then
                        fn_log_info "Cutting off the file $1"
                        mv $1 $1.old || fn_out_warn "Moving file $1 failed"
                fi
        else
                fn_log_warn "$1 not found"
        fi
}

fn_check_dir() {
        ## Check whether direcotry exists
        if [ $# -eq 1 ]; then
                if [ ! -d $1 ]; then
                        fn_log_error "$1 not found. exit"
                        return 2
                else
                        return 0
                fi

        else
                fn_log_err "Need 1 parameter for check_dir function"
                return 3
        fi
        #return 0
}

fn_move2stg() {
        ## Move the file to stg/ folder

        ## To Judge whether it has files in OUTDIR
        FILES=$(ls $OUTDIR)
        if [ ! -z "$FILES" ]; then
                ## Logging the FILE information
                fn_log_info " - move2stg " >> $OUTFILE
                if [ ! -z "$MULTIS" ]; then
                        TOTAL=$(ls $OUTDIR/|wc -l)
                        NO=$(expr $TOTAL / $MULTIS)
                        IFS_ORG=$IFS
                        IFS=","
                        for INST in $INSTID
                        do
                                CDASTG_DIR=$SENDDIR/$INST/stg
                                fn_check_dir $CDASTG_DIR || exit 2
                                # Move NO files from out to CDA stg/
                                fn_log_info "Move $NO files from $OUTDIR to $CDASTG_DIR"
                                ls $OUTDIR/* |head -$NO |xargs -r -I {} mv {} $CDASTG_DIR 2>>$LOGFILE
                        done
                        IFS=$IFG_ORG

                        ## If still exists files on out folder and move it to stg/ in last CDA instance
                        if [ ! -z "$(ls $OUTDIR)" ]; then
                                CDASTG_DIR=$SENDDIR/$INST/stg
                                fn_check_dir $CDASTG_DIR || exit 2
                                # Move NO files from out to CDA stg/
                                fn_log_info "Move $(ls $OUTDIR|wc -l) files from $OUTDIR to $CDASTG_DIR"
                                ls $OUTDIR/* |xargs -r -I {} mv {} $CDASTG_DIR 2>>$LOGFILE
                        fi

                fi
        fi
}

fn_move2out() {
    ## Move the file from stg/ to out/ folder
        if [ ! -z "$MULTIS" ]; then
                ## Logging the FILE information
                fn_log_info " - move2out " >> $OUTFILE
                IFS_ORG=$IFS
                IFS=","
                for INST in $INSTID
                do
                        CDASTG_DIR=$SENDDIR/$INST/stg
                        fn_check_dir $CDASTG_DIR || exit 2

                        ## To Judge whether it has files in STGDIR
                        if [ ! -z "$(ls ${CDASTG_DIR})" ]; then

                                CDACMP_DIR=$SENDDIR/$INST/cmp
                                CDAOUT_DIR=$SENDDIR/$INST/${PREFIX}out

                                fn_check_dir $CDACMP_DIR || exit 2
                                fn_check_dir $CDAOUT_DIR || exit 2

                                # Move NO. files from stg/ to sout/ for standby server
                                if [ "$PS_FLAG" == "-s" ]; then
                                        # If it's standby, not additional process
                                        fn_log_info "Move $(ls ${CDASTG_DIR}|wc -l) files from $CDASTG_DIR to $CDAOUT_DIR"
                                        ls $CDASTG_DIR/* |xargs -r -I {} mv {} $CDAOUT_DIR 2>>$LOGFILE
                                else
                                        # Move suitable files count for CDA if it's primary
                                        CMP_CNT=$(ls -l $CDACMP_DIR/__cda* 2>/dev/null|wc -l)
                                        OUT_CNT=$(ls $CDAOUT_DIR 2>/dev/null|wc -l)
                                        STG_CNT=$(ls $CDASTG_DIR 2>/dev/null|wc -l)
                                        if [ $CMP_CNT -le $THRESHOLD -a $OUT_CNT -le $THRESHOLD ]; then
                                                STG_CNT=$(ls $CDASTG_DIR|wc -l)
                                                if [ $STG_CNT -le $THRESHOLD ]; then
                                                # If the No. less threshold value, move it directly
                                                        fn_log_info "Move $(ls $CDASTG_DIR|wc -l) files from $CDASTG_DIR to $CDAOUT_DIR"
                                                        mv $CDASTG_DIR/* $CDAOUT_DIR 2>>$LOGFILE
                                                else
                                                        # If more than threshold files, only move files with No.=threshold
                                                        fn_log_info "Move $THRESHOLD files from $CDASTG_DIR to $CDAOUT_DIR"
                                                        ls $CDASTG_DIR/* |head -$THRESHOLD |xargs -r -I {} mv {} $CDAOUT_DIR
                                                fi
                                        else
                                                fn_log_info "Backlog on CDA(cmp/=$CMP_CNT,out/=$OUT_CNT,stg/=$STG_CNT), Not move file"
                                        fi
                                fi
                        fi
                done
                IFS=$IFG_ORG
        fi
}

SENDDIR=/dataout/cda/send
LOGFILE=$PP/$PN.log
OUTFILE=$PP/$PN.txt

## Add it on v1.3 to let CDA never has backlog
## 50 as default value - The cronjob run per 2 minutes
## It's the best value for CDA send 2-3 files per 5 seconds
THRESHOLD=50

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

        fn_check_dir $OUTDIR || exit 2

        ## For multi-instance separated by ,
        MULTIS=$(echo $INSTID|awk -F\, '{print NF}')

        ## Default prefix is -p
        if [ "$PS_FLAG" == "-p" ]; then
                PREFIX=""
        elif [ "$PS_FLAG" == "-s" ]; then
                PREFIX="s"
        else
                fn_log_error "The parameter would be -p or -s"
                fn_usage
                exit 1
        fi

        ## Move files from out to CDA stg/
        fn_move2stg
        ## Move files from stg/ to out/ for CDA
        fn_move2out

fi

[ -f $LOGFILE ] && fn_log_rotate $LOGFILE
[ -f $OUTFILE ] && fn_out_rotate $OUTFILE
exit 0


