### Backup project (app) & mysql database

### Usage
```
 git clone https://github.com/neputertech/app-db-backup.git ~/app-db-backup

 cd ~/app-db-backup/please-do-not-delete/scripts

 find ./* -name "*.sh" | xargs chmod +x

 cp .env.example .env
 cp .mysqldumpcred.example .mysqldumpcred

```


#### For the skeleton I'm using default variables & value. Please change according to your need

1. Copy [.env.example](./please-do-not-delete/scripts/.env.example) as show in above and change the values. 

2. Copy [.mysqldumpcred.example](./please-do-not-delete/scripts/.mysqldumpcred.example) as show in above and change the values. 

## Cronjob
> To set up cronjob, use any of your convenient time    
> Recommended (**at night**)
```
0 23 * * * cd /home/user/app-db-backup/please-do-not-delete/scripts && ./dbbackup.sh  > /home/user/app-db-backup/please-do-not-delete/logs/dbbackup.log 2>&1

2 23 * * * cd /home/user/app-db-backup/please-do-not-delete/scripts && ./appbackup.sh > /home/user/app-db-backup/please-do-not-delete/logs/appbackup.log 2>&1
```