root@vm1113568:~/autonf# cat pushphoto.sh 
if [ "$#" -eq 0 ]
then
        echo 'message required'
        exit 0
fi


TOKEN=xxxxxx   #TG机器人token
chat_ID=xxxxxx              #用户ID或频道、群ID
message_text=$*         #要发送的信息
MODE='HTML'             #解析模式，可选HTML或Markdown
URL="https://api.telegram.org/bot${TOKEN}/sendPhoto"            #api接口
#测试2：终端无日志
#curl -s -o /dev/null -X POST $URL -d chat_id=${chat_ID} -d text="${message_text}"
#echo $message_text
curl -s -X POST $URL -F chat_id=$chat_ID -F photo="${message_text}"
