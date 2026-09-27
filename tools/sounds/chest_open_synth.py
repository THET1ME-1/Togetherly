# Звук открытия сундука («Фанфара», выбран 28.09.2026 из четырёх, макет
# https://claude.ai/artifact/5pJvuP4vVHMxnqn4Wgads4). Синтез с нуля, без чужих
# сэмплов. Длина равна анимации открытия (3,8 с): звук стартует с её первым
# кадром. Запуск: python3 tools/sounds/chest_open_synth.py → chest_open.m4a;
# положить в assets/sounds/.
# Раскадровка: 0–0,9 с сундук дрожит, 1,0–1,35 крышка, 1,3–2,1 приз
# поднимается, 2,0 — «выпало».
import numpy as np, subprocess, os
SR=44100; T=3.8
rng=np.random.default_rng(7)
def f(n): return 440*2**((n-69)/12)          # MIDI → Гц
def t(d): return np.arange(int(d*SR))/SR
def env(d,a=0.005,dec=0.6):
    x=t(d); return np.minimum(1,x/a)*np.exp(-x/dec)
def bell(n,d=1.6,dec=0.55,g=1):             # колокольчик/челеста: негармоничные призвуки
    x=t(d); fr=f(n)
    s=sum(a*np.sin(2*np.pi*fr*r*x)*np.exp(-x/(dec*k)) for r,a,k in [(1,1,1),(2,0.45,0.6),(3.01,0.25,0.4),(4.2,0.12,0.25),(5.4,0.06,0.2)])
    return g*s*np.minimum(1,x/0.004)
def pluck(n,d=0.6,g=1):                      # щипок (Карплус–Стронг)
    N=int(SR/f(n)); buf=rng.uniform(-1,1,N); out=np.zeros(int(d*SR))
    for i in range(len(out)):
        out[i]=buf[i%N]; buf[i%N]=0.5*(buf[i%N]+buf[(i+1)%N])*0.996
    return g*out
def brass(n,d=0.3,g=1):                      # «медь»: гармоники без наложения частот, мягкая атака
    x=t(d); fr=f(n); vib=1+0.004*np.sin(2*np.pi*5.5*x)
    ph=2*np.pi*fr*np.cumsum(vib)/SR
    y=sum(np.sin(k*ph)/k*np.exp(-(k*fr)/3500) for k in range(1,int(9000/fr)+1))
    e=np.minimum(1,x/0.03)*np.minimum(1,(d-x)/0.06).clip(0)*(0.85+0.15*np.exp(-x/0.1))
    return g*y*e
def sparkle(n_blips=10,d=0.9,g=0.25):        # искры: короткие высокие звоночки
    out=np.zeros(int(d*SR))
    for _ in range(n_blips):
        st=int(rng.uniform(0,d-0.15)*SR); fr=rng.uniform(2600,5200); x=t(0.15)
        b=np.sin(2*np.pi*fr*x)*np.exp(-x/0.035); out[st:st+len(b)]+=b*rng.uniform(0.5,1)
    return g*out
def whoosh(d=0.45,g=0.2):                   # мягкий взлёт: шум с поднимающимся фильтром
    x=t(d); noise=rng.normal(0,1,len(x)); y=np.zeros_like(noise)
    for i in range(1,len(noise)):
        a=0.01+0.25*(i/len(noise))**1.5; y[i]=y[i-1]+a*(noise[i]-y[i-1])
    return g*y*np.sin(np.pi*x/d)**2
def put(buf,s,at):
    i=int(at*SR); buf[i:i+len(s)]+=s[:max(0,len(buf)-i)]
def save(name,buf):
    buf=buf/np.max(np.abs(buf))*0.85
    fade=int(0.3*SR); buf[-fade:]*=np.linspace(1,0,fade)
    subprocess.run(['ffmpeg','-y','-loglevel','error','-f','f32le','-ar',str(SR),'-ac','1','-i','-',
                    '-af','aecho=0.8:0.5:60:0.18,loudnorm=I=-15:TP=-1.5,aformat=channel_layouts=stereo',f'{name}.wav'],input=buf.astype(np.float32).tobytes(),check=True)
    for ext,codec in [('mp3',['-b:a','96k']),('m4a',['-c:a','aac','-b:a','96k'])]:
        subprocess.run(['ffmpeg','-y','-loglevel','error','-i',f'{name}.wav',*codec,f'{name}.{ext}'],check=True)
    print(name,os.path.getsize(f'{name}.m4a'))

C5,E5,G5,C6,E6,G6,C7=72,76,79,84,88,91,96
# 2. «Фанфара»: та-та-та-таа медью, как на победе в игре
b=np.zeros(int(T*SR))
put(b,whoosh(0.45,0.25),0.9)
for i,n in enumerate([G5-12+12,G5,G5]): put(b,brass(G5-5 if False else n,0.11,0.55),1.3+i*0.13)
for n in [C5,E5,G5,C6]: put(b,brass(n,1.0,0.35),1.72)
put(b,bell(C7,1.4,0.6,0.25),2.0)
put(b,sparkle(10,1.0,0.16),1.95)
save('chest_open',b)

