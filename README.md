# Natix
Nat Tunnel
این یک پروژه NAT ترافیک سرور با سیستم عامل اوبونتو که قراره کلی روش کار کنیم و گسترشش بدیم

```
sysctl net.ipv4.ip_forward=1
iptables -t nat -A PREROUTING -p tcp --dport 22 -j DNAT --to-destination SERVER_IP
iptables -t nat -A PREROUTING -j DNAT --to-destination OUT_IP
iptables -t nat -A POSTROUTING -j MASQUERADE
```
