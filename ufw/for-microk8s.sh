sudo ufw allow from <worker-ip> to any port 4789 proto udp   # Calico VXLAN (pod-to-pod traffic)
sudo ufw allow from <worker-ip> to any port 16443 proto tcp  # API server
sudo ufw allow from <worker-ip> to any port 10250 proto tcp  # kubelet
sudo ufw allow from <worker-ip> to any port 25000 proto tcp  # cluster agent (joining nodes)
sudo ufw allow from <worker-ip> to any port 19001 proto tcp  # dqlite (HA datastore)
