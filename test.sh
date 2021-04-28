#! /bin/bash

test() {
   for ((;;));do
          echo "1.一键安装全部"
          echo "2.安装nginx   http验证tls"
          echo "3.安装nginx   dns验证tls"
          echo "4.安装v2ray和中间件"
          echo "0.退出"
          read -p ">:" choice
          case $choice in
          1)
            echo "1"
            continue;
            echo "2"
            ;;
          2)
            install_basic
            nginx_conf_simple
            auto_install_https
            ;;
          3)
            nginx_conf_simple

            ;;
          4)
            install_vmanager
            install_service
            uninstall
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


test
