Скачать Клинические рекомендации для СМП
========================================

1) Соберите APK:

   cd C:\src\ambulance\app
   C:\flutter\bin\flutter.bat build apk --release

2) Скопируйте файл сюда под именем app-release.apk:

   C:\src\ambulance\app\build\app\outputs\flutter-apk\app-release.apk
   → C:\src\ambulance\download\app-release.apk

3) Один раз установите генератор QR:

   python -m pip install qrcode


Вариант A. Локальная сеть станции
---------------------------------
   cd C:\src\ambulance\download
   python serve.py

Откройте адрес, который напечатает скрипт, или сканируйте QR.


Вариант B. VPS 147.45.236.228
----------------------------
Подходит, если телефоны должны скачивать приложение из интернета,
а не только из Wi‑Fi станции.

1. Сгенерируйте QR на публичную ссылку APK:

   cd C:\src\ambulance\download
   python make_qr.py --url http://147.45.236.228:8088/

   Если позже появится домен и HTTPS:

   python make_qr.py --url https://ваш-домен.ru/app-release.apk

2. На VPS создайте каталог, например /var/www/smp-download/

3. Загрузите туда файлы:

   index.html
   qr.svg
   app-release.apk

   Пример с Windows (PowerShell / scp):

   scp index.html qr.svg app-release.apk root@147.45.236.228:/var/www/smp-download/

4. Настройте nginx (пример):

   server {
       listen 8088;
       listen [::]:8088;
       server_name 147.45.236.228;

       root /var/www/smp-download;
       index index.html;

       location / {
           try_files $uri $uri/ =404;
       }

       location = /app-release.apk {
           default_type application/vnd.android.package-archive;
           add_header Content-Disposition "attachment; filename=\"smp-guide.apk\"";
       }
   }

5. Откройте на телефоне:

   http://147.45.236.228:8088/

   или сканируйте QR — он открывает эту страницу, кнопка на ней скачивает APK.

Домен smp-guide.com.ru
----------------------
В панели, где куплен домен (раздел DNS, не NS-серверы):

   Тип A, имя @,   значение 147.45.236.228
   Тип A, имя www, значение 147.45.236.228

NS-серверы не заменяйте IP-адресом. Когда
`getent ahostsv4 smp-guide.com.ru` на сервере покажет этот IP,
запустите на VPS (порты 80/443 уже у Caddy проекта gameforge):

   bash /root/caddy_smp.sh

Скрипт лежит рядом: download/caddy_smp.sh
Сайт откроется как https://smp-guide.com.ru/
Порт 8088 можно оставить как запасной адрес.


Замечания по VPS:
- Сейчас с рабочей машины HTTP до этого IP может не открываться
  (фильтр/firewall). На сервере должны быть открыты 80/443 снаружи.
- Лучше повесить домен и HTTPS (Let's Encrypt): магазины и браузеры
  спокойнее относятся к скачиванию по https://.
- Debug-APK на публичный VPS лучше не выкладывать — только release.
- После новой сборки достаточно заменить app-release.apk на сервере;
  QR менять не нужно, пока URL тот же.


На телефоне разрешите установку из браузера / неизвестных источников.
