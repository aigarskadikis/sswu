#!/bin/sh

#this code is tested un fresh 2015-02-09-raspbian-jessie-lite Raspberry Pi image
#by default this script should be located in two subdirecotries under the home

#sudo apt-get update -y && sudo apt-get upgrade -y
#sudo apt-get install git -y
#mkdir -p /home/pi/detect && cd /home/pi/detect
#git clone https://github.com/catonrug/sswu.git && cd sswu && chmod +x check.sh && ./check.sh

#check if script is located in /home direcotry
pwd | grep "^/home/" > /dev/null
if [ $? -ne 0 ]; then
  echo script must be located in /home direcotry
  return
fi

#it is highly recommended to place this directory in another directory
deep=$(pwd | sed "s/\//\n/g" | grep -v "^$" | wc -l)
if [ $deep -lt 4 ]; then
  echo please place this script in deeper directory
  return
fi

#check if global check-all.sh is installed
if [ ! -f "../check-all.sh" ]; then
  echo installing check-all.sh
cat > ../check-all.sh <<EOF
#!/bin/sh
cd \`dirname \$0\`
todo=\$(ls -1 */check.sh | sed '\$aend of file')
printf %s "\$todo" | while IFS= read -r job
do {
workdir=\$(echo \$job | sed "s/\/.*\$//g")
cd \$workdir
./check.sh
cd ..
} done
EOF
chmod +x ../check-all.sh
echo
fi

#check if email sender exists
if [ ! -f "../send-email.py" ]; then
  echo send-email.py not found. downloading now..
  wget https://gist.githubusercontent.com/superdaigo/3754055/raw/e28b4b65110b790e4c3e4891ea36b39cd8fcf8e0/zabbix-alert-smtp.sh -O ../send-email.py -q
  echo
fi

#check if email sender is configured
grep "your.account@gmail.com" ../send-email.py > /dev/null
if [ $? -eq 0 ]; then
  echo username is not configured in ../send-email.py please look at the line:
  grep -in "your.account@gmail.com" ../send-email.py
  echo sed -i \"s/your.account@gmail.com//\" ../send-email.py
  echo
fi

#check if email password is configured
grep "your mail password" ../send-email.py > /dev/null
if [ $? -eq 0 ]; then
  echo password is not configured in ../send-email.py please look at line:
  grep -in "your mail password" ../send-email.py
  echo sed -i \"s/your mail password//\" ../send-email.py
  echo
  return
fi

#check for file where all emails will be used to send messages
if [ ! -f "../posting" ]; then
  echo posting email address not configured. all changes will be submited to all email adresies in this file
  echo echo your.email@gmail.com\> ../posting
  echo
fi

#make sure the maintenance email is configured
if [ ! -f "../maintenance" ]
then
echo maintenance email address not configured. this will be used to check if the page even still exist.
echo echo your.email@gmail.com\> ../maintenance
echo
return
fi

#set application name based on directory name
#this will be used for future temp directory, database name, google upload config, archiving
appname=$(pwd | sed "s/^.*\///g")

#set temp directory in variable based on application name
tmp=$(echo ../tmp/$appname)

#create temp directory
if [ ! -d "$tmp" ]; then
  mkdir -p "$tmp"
fi

#set data directory in variable based on application name
data=$(echo ../data/$appname)

#create data directory
if [ ! -d "$data" ]; then
  mkdir -p "$data"
fi

#check if database directory has prepared 
if [ ! -d "../db" ]; then
  mkdir -p "../db"
fi

#set database variable
db=$(echo ../db/$appname.db)

#if database file do not exist then create one
if [ ! -f "$db" ]; then
  touch "$db"
fi

#set url for all update information
url=$(echo "http://download.windowsupdate.com/microsoftupdate/v6/wsusscan/wsusscn2.cab")

#calculate filename
filename=$(echo "$url" | sed "s/^.*\///g")

#download all information about file on server. this will let us read the modify date of file
wget -S --spider -o $tmp/output.log "$url"

#check if the link even is still alive
grep -A99 "^Resolving" $tmp/output.log | grep "HTTP.*200 OK"
if [ $? -eq 0 ]; then

#there must be Last-Modified field. if not - quit program
grep -A99 "^Resolving" $tmp/output.log | grep "Last-Modified" 
if [ $? -eq 0 ]; then

#take the Last-Modified information
lastmodified=$(grep -A99 "^Resolving" $tmp/output.log | grep "Last-Modified" | sed "s/^.*: //")

#check if we have the latest windows update list. if not then download the latest
grep "$lastmodified" $db
if [ $? -ne 0 ]; then
echo new version of $filename found. cleaning data direcotry now..
rm $data/* -rf > /dev/null
echo re-downloading $filename
wget $url -O $data/$filename -q
7z x $data/$filename -y -o$data
mkdir $data/RevisionId
cablist=$(ls -1 $data/package*cab)
printf %s "$cablist" | while IFS= read -r cab
do {
echo extracting $cab..
7z e $cab "l/en" -y -o$data/RevisionId
} done
else
echo data direcotry is up to date
fi


#put the last modified timestamp in database
echo "$lastmodified">> $db

7z x $data/package.cab -y -o$tmp

echo
sed "s/<Update /\n\n<Update /g" "$tmp/package.xml" | \
grep "SupersededBy" | \
sed "s/^.* RevisionId=/RevisionId=/g" | 
sed "s/RevisionNumber.*RevisionId/RevisionId/g" | \
sed "s/IsLeaf.*<SupersededBy></SupersededBy /g" | \
sed "s/ \/><\/SupersededBy>.*$//g" | \
sed "s/ \/><Revision//g" | \
sed "s/RevisionId=\| Revision\|Id=\|\d034//g" | \
head -10

else
#if link do not include Last-Modified
emails=$(cat ../maintenance | sed '$aend of file')
printf %s "$emails" | while IFS= read -r onemail
do {
python ../send-email.py "$onemail" "To Do List" "the following link do not include Last-Modified: 
$url"
} done
echo 
echo
fi

else
#if http statis code is not 200 ok
emails=$(cat ../maintenance | sed '$aend of file')
printf %s "$emails" | while IFS= read -r onemail
do {
python ../send-email.py "$onemail" "To Do List" "the following link do not retrieve good http status code: 
$url"
} done
echo 
echo
fi

rm $tmp -rf > /dev/null
