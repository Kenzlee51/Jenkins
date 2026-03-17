#!/bin/bash

DUMP_DATE=$(date +"%Y-%m-%d_%H-%M-%S")
DIR_DATE=$(date +"%Y-%m-%d")
SUDO_PASS="12345678"
#BUILD_NUMBER=${BUILD_NUMBER:-1}
COUNTER=$(( ($BUILD_NUMBER - 1) % 4 ))
echo COUNTER=$COUNTER
echo BUILD_NUMBER=$BUILD_NUMBER

cd /home/user/svacer-test
mkdir -p dump/tmp
docker exec -i svacer-postgres pg_dump -U svace svace > dump/tmp/svacer_"$DUMP_DATE".sql 2>log/dump_error_"$DUMP_DATE".log
docker compose stop

#docker run --rm -v svace-object-store:/data/store -v /home/user/svacer-test/dump/tmp:/backup ubuntu tar -czf /backup/svacer-object-store_"$(date +"%Y-%m-#%d_%H-%M-%S")".tar.gz -C /data/store . 2> log/dump_os_error_"$(date +"%Y-%m-%d_%H-%M-%S")".log

docker run --rm -v svacer-object-store:/data/store -v /home/user/svacer-test/dump/tmp:/backup ubuntu tar -czf /backup/svacer-object-store_"$DUMP_DATE".tar.gz -C /data/store .
docker compose up -d


# ---- Монтируем forsonas в системе ----
if ! mountpoint -q /home/user/forsonas; then
echo "$SUDO_PASS" | sudo -S mount -t cifs -o username=kirill_v,password=komusfanvil //192.168.25.230/программное_обеспечение /home/user/forsonas
fi

# ---- Проверяем успешно ли перемонтирован forsonas ----
if ! mountpoint -q /home/user/forsonas; then
echo "[ERROR] НЕ УДАЛОСЬ ПРИМОНТИРОВАТЬ forsonas"
rm -rf dump/tmp
exit 1
fi

# ---- Создаем директорию на форсонасе для дампа ----
# ---- Месячный бэкап ----
if [ "$COUNTER" -eq 3 ]; then
echo "$SUDO_PASS" | sudo -S mkdir -p /home/user/forsonas/DB_dumps/svacer-server/monthly/dump_"$DIR_DATE"
echo "$SUDO_PASS" | sudo -S cp /home/user/svacer-test/dump/tmp/*.sql /home/user/forsonas/DB_dumps/svacer-server/monthly/dump_"$DIR_DATE"
echo "$SUDO_PASS" | sudo -S cp /home/user/svacer-test/dump/tmp/*.tar.gz /home/user/forsonas/DB_dumps/svacer-server/monthly/dump_"$DIR_DATE"

# ---- Недельный бэкап ----
else
echo "$SUDO_PASS" | sudo -S mkdir -p /home/user/forsonas/DB_dumps/svacer-server/weekly/dump_"$DIR_DATE"
echo "$SUDO_PASS" | sudo -S cp /home/user/svacer-test/dump/tmp/*.sql /home/user/forsonas/DB_dumps/svacer-server/weekly/dump_"$DIR_DATE"
echo "$SUDO_PASS" | sudo -S cp /home/user/svacer-test/dump/tmp/*.tar.gz /home/user/forsonas/DB_dumps/svacer-server/weekly/dump_"$DIR_DATE"
fi

# ---- Отмонтируем forsonas ----
echo "$SUDO_PASS" | sudo -S umount /home/user/forsonas

rm -rf dump/tmp