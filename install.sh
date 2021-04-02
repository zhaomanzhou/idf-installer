#! /bin/bash

red='\e[91m'
green='\e[92m'
yellow='\e[93m'
magenta='\e[95m'
cyan='\e[96m'
none='\e[0m'

nginx_conf_simple() {
  cd /etc/nginx/conf.d
  cat >v2ray-manager.conf <<-EOF
server {

  listen 80 ;
  server_name $this_server_name; #修改为自己的IP/域名
  root /opt/jar/web;

  location /api {
    proxy_pass http://127.0.0.1:9091/;
  }

  location /ws/ {
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
  "$HOME"/.acme.sh/acme.sh --install-cert -d ${this_server_name} \
    --key-file /etc/nginx/ssl_cert/${this_server_name}/${this_server_name}.key \
    --fullchain-file /etc/nginx/ssl_cert/${this_server_name}/${this_server_name}.cer \
    --reloadcmd "service nginx force-reload"

  cd /etc/nginx/conf.d || return
  rm -f v2ray-manager.conf
  cat >v2ray-manager.conf <<-EOF
server {
    listen 443 ssl http2;
    server_name $this_server_name;
    root /opt/jar/web;
    ssl_certificate       /etc/nginx/ssl_cert/${this_server_name}/${this_server_name}.cer;
    ssl_certificate_key   /etc/nginx/ssl_cert/${this_server_name}/${this_server_name}.key;
    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
    ssl_ciphers TLS13-AES-128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE:ECDH:AES:HIGH:!NULL:!aNULL:!MD5:!ADH:!RC4;


    location /api {
        proxy_pass http://127.0.0.1:9091/;
    }

    location /ws/ {
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

server {
    listen 80;
    server_name $this_server_name;
    rewrite ^(.*)\$ https://\${server_name}\$1 permanent;
}

EOF
}

dns_https() {
  if [[ -e /root/.acme.sh/acme.sh ]]; then
    echo "监测到已经安装过acme，跳过acme安装"
  else
    curl https://get.acme.sh | sh
    alias acme.sh=~/.acme.sh/acme.sh
    echo 'alias acme.sh=~/.acme.sh/acme.sh' >>/etc/profile
    source /etc/profile
    00 00 * * * root /root/.acme.sh/acme.sh --cron --home /root/.acme.sh &>/var/log/acme.sh.logs
    mkdir -p /etc/nginx/ssl_cert/$this_server_name
  fi
  /root/.acme.sh/acme.sh --issue --dns -d $this_server_name --yes-I-know-dns-manual-mode-enough-go-ahead-please

  read -p "按任意键继续" nonUsed

  if /root/.acme.sh/acme.sh --renew -d $this_server_name --yes-I-know-dns-manual-mode-enough-go-ahead-please; then
      echo "--------------------------"
      echo "验证成功"
      echo "--------------------------"
      install_cer_after_verify
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
    curl https://get.acme.sh | sh
    alias acme.sh=~/.acme.sh/acme.sh
    echo 'alias acme.sh=~/.acme.sh/acme.sh' >>/etc/profile
    source /etc/profile
    00 00 * * * root /root/.acme.sh/acme.sh --cron --home /root/.acme.sh &>/var/log/acme.sh.logs
    mkdir -p /etc/nginx/ssl_cert/$this_server_name
  fi


  if ! "$HOME"/.acme.sh/acme.sh --issue -d $this_server_name --nginx; then
    error "------------------------------"
    error "http验证证书失败"
    error "------------------------------"
    return 11
  fi

  install_cer_after_verify


}

install_vmanager() {

  if ! apt install   openjdk-8-jre  -y; then
    error "安装openjk-8出错"
    return 111
  fi
  # 安装v2ray -来源官网新版
  bash <(curl -L -s https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)


  mkdir /opt/jar -p
  cd /opt/jar

  # 下载releases包
  wget -c https://glare.now.sh/master-coder-ll/v2ray-web-manager/v2ray-proxy -O v2ray-proxy.jar

  # 下载代理服务的配置文件
  wget -c --no-check-certificate https://raw.githubusercontent.com/master-coder-ll/v2ray-web-manager/master/conf/proxy.yaml

  sed -i 's/authPassword/authPassword: 6dbty9rA$ #/g' proxy.yaml
  sed -i 's/127.0.0.1/idofast.com/g' proxy.yaml
  # 下载v2ray的专用配置文件
  wget -c --no-check-certificate https://raw.githubusercontent.com/master-coder-ll/v2ray-web-manager/master/conf/config.json

  mv /usr/local/etc/v2ray/config.json /usr/local/etc/v2ray/config.json.bak

  # 复制配置到v2ray目录
  cp /opt/jar/config.json /usr/local/etc/v2ray/

  # 重启v2ray
  service v2ray restart
}

install_service() {


  if [ -e /opt/jar/v2panel-start.sh ]; then
    error "已将安装过v2panel脚本和服务"
    return 11
  fi


  cat >/opt/jar/v2panel-start.sh <<-EOF
#!/bin/sh
nohup java -jar  /opt/jar/v2ray-proxy.jar --spring.config.location=/opt/jar/proxy.yaml > /dev/null 2>&1 &
echo \$! > /var/run/v2ray-proxy.pid
EOF

  cat >/opt/jar/v2panel-stop.sh <<-EOF
#!/bin/sh
PID1=\${cat /var/run/v2ray-admin.pid}
kill -15 $PID1
PID2=\${cat /var/run/v2ray-proxy.pid}
kill -15 $PID2
EOF

  cat >/etc/systemd/system/v2panel.service <<-EOF
[Unit]
Description=v2ray-web-manager
After=network.target network-online.target nss-lookup.target mysql.service mariadb.service mysqld.service
[Service]
Type=forking
StandardError=journal
ExecStart=/opt/jar/v2panel-start.sh
ExecStop=/opt/jar/v2panel-stop.sh
[Install]
WantedBy=multi-user.target
EOF

  chmod a+x /opt/jar/v2panel-start.sh
  chmod a+x /opt/jar/v2panel-stop.sh

  alias start='systemctl start v2panel'
  alias stop='systemctl stop v2panel'
  alias status='systemctl status v2panel'



  echo 'alias start="'"systemctl start v2panel"'"' >>/etc/profile

  echo 'alias stop="'"systemctl stop v2panel"'"' >>/etc/profile

  echo 'alias status="'"systemctl status v2panel"'"' >>/etc/profile

  source /etc/profile

  systemctl enable v2ray
  systemctl enable v2panel

  echo "0 0 */3 * * /sbin/shutdown -r" >>/var/spool/cron/crontabs/root
  systemctl restart cron

}

error() {

  local message="输入错误！"
  if [ $# -eq 0 ]; then
    message=$1
  fi
	echo -e "\n$red $message $none\n"

}


install_basic() {
  apt-get update
  # 安装必要软件

  if ! apt install vim net-tools socat wget unzip nginx -y; then
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
          echo "2.安装nginx   不安装证书"
          echo "3.安装nginx   http验证tls"
          echo "4.安装nginx   dns验证tls"
          echo "5.安装v2ray和中间件"
          echo "6.安装基本环境"
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
            ;;
          2)
              nginx_conf_simple
            ;;
          3)
            nginx_conf_simple
            auto_install_https
            ;;
          4)
            nginx_conf_simple
            dns_https
            ;;
          5)
            install_vmanager
            install_service
            ;;
          6)
            install_basic
            ;;
          0)
            exit 0;
            ;;
          *)
            error
            ;;
          esac
  done

}

menu


