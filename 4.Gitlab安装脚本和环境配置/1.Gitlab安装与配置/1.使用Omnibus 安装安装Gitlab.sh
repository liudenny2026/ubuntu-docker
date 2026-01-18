
# 1. 添加清华大学镜像源
sudo apt update
sudo apt install -y curl openssh-server ca-certificates tzdata perl

# 2. 创建镜像源配置文件
sudo tee /etc/apt/sources.list.d/gitlab-ce.list <<'EOF'
deb https://mirrors.tuna.tsinghua.edu.cn/gitlab-ce/ubuntu noble main
EOF

# 3. 导入GPG密钥
curl -fsSL https://packages.gitlab.com/gitlab/gitlab-ce/gpgkey | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/gitlab.gpg

# 4. 安装指定版本
sudo apt update
sudo apt install -y gitlab-ce=18.7.0-ce.0

# 5. 配置并启动
sudo gitlab-ctl reconfigure


# 6. 确认服务状态
sudo gitlab-ctl status | grep run
run: alertmanager: (pid 19368) 201s; run: log: (pid 18870) 271s
run: gitaly: (pid 19310) 205s; run: log: (pid 18239) 544s
run: gitlab-exporter: (pid 19327) 204s; run: log: (pid 18783) 287s
run: gitlab-kas: (pid 18519) 518s; run: log: (pid 18543) 517s
run: gitlab-workhorse: (pid 19257) 206s; run: log: (pid 18692) 303s
run: logrotate: (pid 18024) 564s; run: log: (pid 18133) 561s
run: nginx: (pid 19285) 206s; run: log: (pid 18725) 300s
run: node-exporter: (pid 19320) 205s; run: log: (pid 18764) 294s
run: postgres-exporter: (pid 19384) 201s; run: log: (pid 18903) 263s
run: postgresql: (pid 18286) 529s; run: log: (pid 18297) 527s
run: prometheus: (pid 19338) 204s; run: log: (pid 18833) 277s
run: puma: (pid 18603) 316s; run: log: (pid 18610) 314s
run: redis: (pid 18177) 553s; run: log: (pid 18190) 550s
run: redis-exporter: (pid 19329) 204s; run: log: (pid 18804) 282s
run: sidekiq: (pid 18619) 310s; run: log: (pid 18627) 309s

root@ubuntuserver:~# sudo ss -tuln | grep -E ':(80|443)'
tcp   LISTEN 0      511          0.0.0.0:80        0.0.0.0:*          
tcp   LISTEN 0      511          0.0.0.0:8060      0.0.0.0:*          
tcp   LISTEN 0      1024       127.0.0.1:8080      0.0.0.0:*          
tcp   LISTEN 0      2048       127.0.0.1:8082      0.0.0.0:*          
tcp   LISTEN 0      2048       127.0.0.1:8092      0.0.0.0:* 
 
 7.设置默认开启启动
 sudo systemctl is-enabled gitlab-runsvdir.service
 sudo systemctl enable gitlab-runsvdir.service

 8.查看默认密码
 more /etc/gitlab/initial_root_password