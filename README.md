# Natix
Nat Tunnel
<br>
<div align="right">
نیتیکس یک پروژه عبور ترافیک با سیستم عامل اوبونتو لینوکسه که قراره کلی روش کار کنیم و گسترشش بدیم
</div>
<br>
<div align="left">
  
```
sysctl net.ipv4.ip_forward=1
iptables -t nat -A PREROUTING -p tcp --dport 22 -j DNAT --to-destination SERVER_IP
iptables -t nat -A PREROUTING -j DNAT --to-destination OUT_IP
iptables -t nat -A POSTROUTING -j MASQUERADE
```
</div>
<br>
<div align="right">
در اینجا اگر به جای SERVER_IP آی پی سرور و به جای OUT_IP آی پی سرور خارج رو بزاری کل ترافیک سرور به غیر از پورت 22 به خارج هدایت میشه، ما در اینجا پورت SSH سرور ایران رو 22 در نظر گرفتیم اگر شما پورت SSH سرور خودتون رو تغییر دادید اینجا هم 22 رو تغییر بدید
</div>
