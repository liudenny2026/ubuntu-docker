 
sudo mkdir -p /home/ubuntu/gitlab/config
sudo mkdir -p /home/ubuntu/gitlab/logs
sudo mkdir -p /home/ubuntu/gitlab/data

chmod 777 /home/ubuntu/gitlab/config
chmod 777 /home/ubuntu/gitlab/logs
chmod 777 /home/ubuntu/gitlab/data

docker pull swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/gitlab/gitlab-ce:18.7.0-ce.0

docker tag  swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/gitlab/gitlab-ce:18.7.0-ce.0  docker.io/gitlab/gitlab-ce:18.7.0-ce.0

docker-compose up -d


# 默认账号root 密码查看
docker exec -it container-id容器名称 cat /etc/gitlab/initial_root_password


