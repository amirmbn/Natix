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
<div align="right">
در اینجا اگر به جای SERVER_IP آی پی سرور و به جای OUT_IP آی پی سرور خارج رو بزاری کل ترافیک سرور به غیر از پورت 22 به خارج هدایت میشه، ما در اینجا پورت SSH سرور ایران رو 22 در نظر گرفتیم اگر شما پورت SSH سرور خودتون رو تغییر دادید اینجا هم 22 رو تغییر بدید
<br><br>
اهداف فعلی پروژه:
- شناسایی آی پی سرور به صورت اتوماتیک
- امکان تنظیم پورت و آی پی های مختلف
- حالت راه اندازی اتوماتیک سرویس بعد از ریستارت سرور
- ذخیره تنظیمات اعمالی در سرور
</div>

<div align="right">

- با استفاده از نام کاربری admin، رمز عبور 1234 و پورت 1000 ( Server-IP:1000 ) وارد پنل شوید.
- درصورت تانل، داخل تنظیمات Peer Remote Endpoint را به IP ایران تغییر دهید
- برای راه اندازی تانل سرور ایران و خارج میتوانید از [UDP2RAW](https://github.com/amirmbn/UDP2RAW) استفاده کنید
- اگر از سرورهای دیجیتال اوشن استفاده میکنید، نصب دستی پنل وایرگارد را دنبال کنید.
</div><br>
