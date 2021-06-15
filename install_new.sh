#! /bin/bash

red='\e[91m'
green='\e[92m'
yellow='\e[93m'
magenta='\e[95m'
cyan='\e[96m'
none='\e[0m'

nginx_conf_simple() {

  local that_port=80
  if [ $# -gt 0 ]; then
      read -p "请输入http端口" that_port
  fi
  systemctl enable nginx;
  systemctl start nginx;

  cd /etc/nginx/conf.d
  cat >v2ray-manager.conf <<-EOF
server {

  listen $that_port ;
  server_name $this_server_name; #修改为自己的IP/域名

  location /api {
    proxy_pass http://127.0.0.1:9091/;
  }

  location /idf/ {
    proxy_redirect off;
    proxy_pass http://127.0.0.1:8081;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$http_host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }

}
EOF

  nginx -s reload

}



install_cer_after_verify() {

    local that_port=443
    if [ $# -gt 0 ]; then
      that_port=$1
    fi

  "$HOME"/.acme.sh/acme.sh --install-cert -d ${this_server_name} \
    --key-file /etc/nginx/ssl_cert/${this_server_name}/${this_server_name}.key \
    --fullchain-file /etc/nginx/ssl_cert/${this_server_name}/${this_server_name}.cer \
    --reloadcmd "service nginx force-reload"

  cd /etc/nginx/conf.d || return
  rm -f v2ray-manager.conf

  mkdir -p /var/www/letsencrypt

  chmod a+w /var/www/letsencrypt

  cat >v2ray-manager.conf <<-EOF
server {
    listen $that_port ssl http2;
    server_name $this_server_name;
    root /opt/idf/web;
    ssl_certificate       /etc/nginx/ssl_cert/${this_server_name}/${this_server_name}.cer;
    ssl_certificate_key   /etc/nginx/ssl_cert/${this_server_name}/${this_server_name}.key;
    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
    ssl_ciphers TLS13-AES-128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE:ECDH:AES:HIGH:!NULL:!aNULL:!MD5:!ADH:!RC4;




    location /idf/ {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:8888;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}

server {
    listen 80;
    server_name ${this_server_name};
    location /.well-known/acme-challenge {
                root /var/www/letsencrypt;
        }

        location / {
                return 301 https://\$host\$request_uri;
        }
}

EOF

nginx -s reload
}

dns_https() {

  declare nginx_https_port;
  read -p "请输入https端口" nginx_https_port


  if [ -z $nginx_https_port ]; then
    echo "https端口设置为默认443"
    nginx_https_port=443
  fi

  if [[ -e /root/.acme.sh/acme.sh ]]; then
    echo "监测到已经安装过acme，跳过acme安装"
  else
    curl https://get.acme.sh | sh
    alias acme.sh=~/.acme.sh/acme.sh
    if [[ -z `cat /etc/profile | grep  'acme.sh'` ]]; then
      echo 'alias acme.sh=~/.acme.sh/acme.sh' >>/etc/profile
    fi
    source /etc/profile
    00 00 * * * root /root/.acme.sh/acme.sh --cron --home /root/.acme.sh &>/var/log/acme.sh.logs
  fi

  mkdir -p /etc/nginx/ssl_cert/$this_server_name
  /root/.acme.sh/acme.sh --issue --dns -d $this_server_name --yes-I-know-dns-manual-mode-enough-go-ahead-please

  read -p "按任意键继续" nonUsed
  read -p "按任意键继续" nonUsed

  if /root/.acme.sh/acme.sh --renew -d $this_server_name --yes-I-know-dns-manual-mode-enough-go-ahead-please; then
      echo "--------------------------"
      echo "验证成功"
      echo "--------------------------"
      install_cer_after_verify $nginx_https_port
  else
      error "------------------------------"
      error "dns验证证书失败"
      error "------------------------------"
      return 111
  fi
}

auto_install_https() {

  if [[ -e /root/.acme.sh/acme.sh ]]; then
    echo "监测到已经安装过acme，跳过acme安装"
  else
    echo "开始安装acme"
    curl https://get.acme.sh | sh
    alias acme.sh=~/.acme.sh/acme.sh
    echo 'alias acme.sh=~/.acme.sh/acme.sh' >>/etc/profile
    source /etc/profile
    00 00 * * * root /root/.acme.sh/acme.sh --cron --home /root/.acme.sh &>/var/log/acme.sh.logs
    /root/.acme.sh/acme.sh --register-account -m zmzsstreet@gmail.com
  fi
    mkdir -p /etc/nginx/ssl_cert/$this_server_name


  if ! "$HOME"/.acme.sh/acme.sh --issue -d $this_server_name --nginx; then
    error "------------------------------"
    error "http验证证书失败"
    error "------------------------------"
    return 11
  fi

  install_cer_after_verify


}

install_vmanager() {


  # 安装v2ray -来源官网新版
  bash <(curl -L -s https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)

  mkdir /opt/idf -p
  cd /opt/idf


  wget -c https://github.com/zhaomanzhou/idf-manager/releases/download/0.2/idf-proxy-2.0.jar  -O proxy.jar



  # 下载v2ray的专用配置文件
  wget https://raw.githubusercontent.com/zhaomanzhou/idf-manager/master/idf-proxy/src/main/resources/application-prod.yaml

  sed -i "s/agajp.idofast.com/${this_server_name}/g" application-prod.yaml


  wget -c --no-check-certificate https://raw.githubusercontent.com/zhaomanzhou/idf-manager/master/idf-proxy/src/main/resources/config.json

  mv /usr/local/etc/v2ray/config.json /usr/local/etc/v2ray/config.json.bak

  # 复制配置到v2ray目录
  cp /opt/idf/config.json /usr/local/etc/v2ray/


  # 重启v2ray
  systemctl restart v2ray
}

install_service() {


  if [ -e /opt/idf/v2-start.sh ]; then
    error "已将安装过v2panel脚本和服务"
    return 11
  fi


 cat > /opt/idf/v2-start.sh <<-EOF
#!/bin/sh
cd /opt/idf
nohup java -jar  /opt/idf/proxy.jar --spring.profiles.active=prod > /dev/null 2>&1 &
echo \$! > /var/run/v2ray-proxy.pid
EOF

  cat > /opt/idf/v2-stop.sh <<-EOF
#!/bin/sh
PID2=\${cat /var/run/v2ray-proxy.pid}
kill -15 $PID2
EOF


  cat > /etc/systemd/system/proxy.service <<-EOF
[Unit]
Description=idf-manager
After=network.target network-online.target nss-lookup.target mysql.service mariadb.service mysqld.service
[Service]
Type=forking
StandardError=journal
ExecStart=/opt/idf/v2-start.sh
ExecStop=/opt/idf/v2-stop.sh
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
  chmod a+x /opt/idf/v2-start.sh
  chmod a+x /opt/idf/v2-stop.sh

  alias start='systemctl start proxy'
  alias stop='systemctl stop proxy'
  alias status='systemctl status proxy'

  echo 'alias start="'"systemctl start proxy"'"' >>/etc/profile

  echo 'alias stop="'"systemctl stop proxy"'"' >>/etc/profile

  echo 'alias status="'"systemctl status proxy"'"' >>/etc/profile

  source /etc/profile
  systemctl enable nginx
  systemctl enable v2ray
  systemctl enable proxy


  #echo "0 0 */3 * * /sbin/shutdown -r" >>/var/spool/cron/crontabs/root
  systemctl restart cron

}

error() {

  local message="输入错误！"
  if [ $# -gt 0 ]; then
    message=$1
  fi
	echo -e "\n$red $message $none\n"

}


install_bbr()
{
  if [[ -n $(lsmod | grep bbr) ]]; then
              echo "bbr 已开启 "
      return 0;
  fi

  echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
  sysctl   -p
  echo "查看是否开启"
  sysctl net.ipv4.tcp_available_congestion_control
  echo "查看是否启动"
  lsmod | grep bbr
}

install_basic() {
  apt-get update
  # 安装必要软件

  if ! apt install vim net-tools socat wget curl unzip  openjdk-11-jdk  nginx -y; then
    error "安装vim net-tools wget unzip nginx失败"
    exit 1
  fi

}

menu() {
  echo "........... idf一键安装脚本  .........."
  if [ -z $this_server_name ]; then
    echo "未监测到本机域名，请输入域名前缀 _.idofast.com"
    read server_prefix
    echo "export this_server_name=${server_prefix}.idofast.com" >>/etc/profile
    source /etc/profile

  else
    echo "监测到主机域名为$this_server_name"
  fi


  for ((;;));do
          echo "1.一键安装全部"
          echo "2.安装基本环境"
          echo "3.安装nginx   不安装证书"
          echo "4.http安装nginx证书"
          echo "5.dns安装ngin证书"
          echo "6.安装v2ray和中间件"
          echo "7.查看nginx日志"
          echo "8.查看中间件日志"
          echo "9.开启bbr"
          echo "10.一键安装全部，dns校验"
          echo "0.退出"
          read -p ">:" choice
          case $choice in
          1)
            if ! install_basic ; then
              continue ;
            fi


            if ! nginx_conf_simple; then
              continue;
            fi

            if ! auto_install_https; then
              continue;
            fi
            install_vmanager
            install_service
            install_bbr

            ;;
          2)
            install_basic
            ;;
          3)
              nginx_conf_simple ask
            ;;
          4)
            nginx_conf_simple
            auto_install_https
            ;;
          5)
            nginx_conf_simple
            dns_https
            ;;
          6)
            install_vmanager
            install_service
            ;;

          7)
              tail -f /var/log/nginx/access.log
            ;;
          8)
              tail -f /opt/jar/logs/v2ray-proxy.log
            ;;
          9)

            install_bbr
            ;;
          0)
            exit 0;
            ;;
          10)
            if ! install_basic ; then
              continue ;
            fi


            if ! nginx_conf_simple; then
              continue;
            fi

            if ! dns_https; then
              continue;
            fi
            install_vmanager
            install_service
            install_bbr

            ;;
          *)
            error
            ;;
          esac
  done

}

menu


