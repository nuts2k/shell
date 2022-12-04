export TERM=${TERM:-dumb}
echo '0' | ~/check.sh -M 6 > ~/autonf/checkres.txt
res=`cat ~/autonf/checkres.txt | grep --color=never Netflix: | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g" | awk '{ print $4 }'`
#echo $res
oldstate=`cat ~/autonf/oldstate.txt`
#echo $oldstate
echo $res > ~/autonf/oldstate.txt
if [[ "$res" == "Yes" ]]
then
        echo $(date +%Y-%m-%d" "%H:%M:%S) OK
        if [[ "$res" != "$oldstate" ]]
        then
        ~/autonf/pushtg.sh xxxx解锁恢复了
        fi
else
        echo $(date +%Y-%m-%d" "%H:%M:%S) Failed
        if [[ "$oldstate" == "Yes" ]]
        then
        ~/autonf/pushtg.sh xxxx解锁掉了
        fi
fi
