#!/bin/bash

CU=$(whoami)
LOG=/var/log/live_update.log
LOGPR=$(sudo find /var/log -type f -name "live_update.log" -exec echo "YES" \;)
if [ "$LOGPR" == "YES" ];then
    echo "Log file is present"
else
    sudo touch $LOG
fi
sudo chown $CU:$CU $LOG 

OS=$(cat /etc/os-release | grep "^NAME" | cut -d "=" -f 2 | sed 's|"||')

if command -v pv &>/dev/null; then
        echo "PV command is present"
else
        if [ $OS = Ubuntu ]; then
                sudo apt install pv -y
        else
                sudo dnf install pv -y
        fi
fi

if command -v tree &>/dev/null; then
        echo "Tree command is present"
else
        if [ $OS = Ubuntu ]; then
                sudo apt install tree -y
        else
                sudo dnf install tree -y
        fi
fi

echo -e "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~LIVE UPDATE STARTED~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n" >> $LOG

read -p "Enter the LIVE UPDATE file link: " L1
read -p "Enter the Project's source directory absolute path: " D1

echo -e "O==========================O\n|$(date '+ %x | %r ')|\nO==========================O\n" >> $LOG

PRNAME=$(basename $D1)
BKTARNAME=$(date '+%d%b%H%M'$PRNAME | tr [:upper:] [:lower:])

ENV=$(sudo find $D1 -type f -name ".env" -exec ls {} \;)

db() {
    grep "^$1" "$ENV" | cut -d "=" -f 2 | sed 's|"||g'
}

DB_HOST=$(db DB_HOST)
DB_PORT=$(db DB_PORT)
DB_DATABASE=$(db DB_DATABASE)
DB_USERNAME=$(db DB_USERNAME)
DB_PASSWORD=$(db DB_PASSWORD)
echo -e "[mysql]\nuser=$DB_USERNAME\npassword=$DB_PASSWORD\nhost=$DB_HOST\nport=$DB_PORT\n[mysqldump]\nuser=$DB_USERNAME\npassword=$DB_PASSWORD\nhost=$DB_HOST\nport=$DB_PORT" > ~/.my.cnf
BKSQLNAME=$(date '+%d%b%H%M'$DB_DATABASE.sql | tr [:upper:] [:lower:])


cd ~
mkdir -p ~/LIVUP
cd LIVUP
LIVDIR=$(pwd)
wget $L1
tar -xzvf $(basename $L1)
diffdir=$LIVDIR/$(echo $(basename $L1) | sed 's\.tar.gz\\')


cd ~
mkdir -p BACKUP && cd BACKUP && mkdir -p PR-BACKUP DB-BACKUP
cd $diffdir
ZF=$(sudo find . -type f | tr '\n' ' ') 
read -p "Enter 'E' to backup entire project or 'U' to backup only updating files: " BC

if [ "$BC" == "E" ];then
    cd ~/BACKUP/PR-BACKUP
    sudo tar Pcf - $D1 | pv -s $(du -sb $D1 | awk '{print $1}') | gzip > $BKTARNAME.tar.gz
elif [ "$BC" == "U" ];then
    cd $D1
    sudo zip -r ~/BACKUP/PR-BACKUP/$BKTARNAME.zip $ZF
fi


cd ~


cd $diffdir
tree | tee -a $LOG
echo -e "\n" >> $LOG
echo -e "\e[32m$" 
sudo cp -rvf  * $D1 | tee -a $LOG
echo -e "\e[0m"
echo -e "\n"

cd ~
echo -e "\e[31m$(rm -rfv $LIVDIR)\e[0m"


cd $D1
sudo chown -R $CU:$CU $D1
sudo chmod -R 777 storage public bootstrap/cache resources modules_statuses.json


read -p "To run additional Artisan commands enter 'y' or 'n' to skip: " PA
if [ $PA == y ]; then
    cd ~/BACKUP/DB-BACKUP
    mysqldump $DB_DATABASE | pv > $BKSQLNAME
        while [ $PA == y ];do
            read -p "Enter the query without 'php artisan' or 'exit' For no query: " PAC
                if [ "$PAC" != "exit" ];then
                    cd $D1
                    php artisan $PAC
                else
                    echo "No PHP Artisan Queries Left"
                    break
                fi
        done
else
    echo "No PHP Artisan command inputs are available"
fi


read -p "To run MySQL query, enter 'y' or 'n' to skip: " MQ
if [ $PA == y ] && [ $MQ == y ];then
    while [ $MQ == y ];do
        read -p "Enter MySQL Query or 'exit' For no query: " MYQ
        if [ "$MYQ" != "exit" ];then
            mysql $DB_DATABASE -e "$MYQ"
        else
            echo "No MySQL Queries Left"
            break
        fi
    done
elif [ $PA == n ] && [ $MQ == y ];then
    cd ~/BACKUP/DB-BACKUP
    mysqldump $DB_DATABASE | pv > $BKSQLNAME
        while [ $MQ == y ];do
        read -p "Enter MySQL Query or 'exit' For no query: " MYQ
        if [ "$MYQ" != "exit" ];then
            mysql $DB_DATABASE -e "$MYQ"
        else
            echo "No MySQL Queries Left"
            break
        fi
    done
else
    echo "No MySQL Query inputs are available"
fi

php $D1/artisan optimize:clear
php $D1/artisan cache:clear


cd ~/BACKUP
sudo find . -type f -mtime +2 -exec rm {} \;
cd ~


PV=$(php -r 'echo PHP_VERSION;' | cut -d "." -f 1,2) 
if [ $OS == Ubuntu ]; then
    sudo chown -R www-data:www-data $D1
    sudo systemctl restart apache2 
    if [ $PV == 8.3 ]; then
        sudo systemctl restart php8.3-fpm
    else
        sudo systemctl restart php8.1-fpm
    fi
else
    sudo chown -R apache:apache $D1
    sudo systemctl restart httpd php-fpm
fi

trap 'rm -rf ~/.my.cnf; echo "Credentials cleaned up"' ERR EXIT INT TERM

echo -e "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~LIVE UPDATE COMPLETED~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n" >> $LOG