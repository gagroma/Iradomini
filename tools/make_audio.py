# Synthesizes every sound effect for the prototype as 22.05 kHz mono 16-bit WAV.
import numpy as np, struct, sys, os
from scipy.signal import butter, lfilter
SR = 22050
rng = np.random.default_rng(3)
out_dir = sys.argv[1]

def t(sec): return np.arange(int(SR*sec))/SR
def noise(sec): return rng.uniform(-1,1,int(SR*sec))
def lp(x,f,o=2): b,a=butter(o,f/(SR/2),'low'); return lfilter(b,a,x)
def hp(x,f,o=2): b,a=butter(o,f/(SR/2),'high'); return lfilter(b,a,x)
def bp(x,f0,f1,o=2): b,a=butter(o,[f0/(SR/2),f1/(SR/2)],'band'); return lfilter(b,a,x)
def env(sec,a,d): 
    x=t(sec); return np.minimum(x/max(a,1e-4),1.0)*np.exp(-np.maximum(x-a,0)/d)
def norm(x,peak=0.9): return x/ (np.max(np.abs(x))+1e-9)*peak
def fade(x,n=200):
    x=x.copy(); n=min(n,len(x)//2); x[:n]*=np.linspace(0,1,n); x[-n:]*=np.linspace(1,0,n); return x
def mix(*parts):
    n=max(len(p) for p in parts); o=np.zeros(n)
    for p in parts: o[:len(p)]+=p
    return o
def at(x,sec,total):
    o=np.zeros(int(SR*total)); i=int(SR*sec); n=min(len(x),len(o)-i); o[i:i+n]+=x[:n]; return o

def write(name,x,loop=False,peak=0.9):
    x=norm(x,peak)
    if not loop: x=fade(x,120)
    pcm=(np.clip(x,-1,1)*32767).astype('<i2').tobytes()
    fmt=struct.pack('<HHIIHH',1,1,SR,SR*2,2,16)
    chunks=b'fmt '+struct.pack('<I',len(fmt))+fmt+b'data'+struct.pack('<I',len(pcm))+pcm
    if loop:
        n=len(pcm)//2
        smpl=struct.pack('<9I',0,0,int(1e9/SR),60,0,0,0,1,0)+struct.pack('<6I',0,0,0,n-1,0,0)
        chunks+=b'smpl'+struct.pack('<I',len(smpl))+smpl
    with open(os.path.join(out_dir,name+'.wav'),'wb') as f:
        f.write(b'RIFF'+struct.pack('<I',4+len(chunks))+b'WAVE'+chunks)
    print(f"{name:14s} {len(x)/SR:5.2f}s {'loop' if loop else ''}")

def seamless(x,xf=0.5):
    # crossfade the tail into the head so the loop has no click
    n=int(SR*xf); head=x[:n]; tail=x[-n:]; w=np.linspace(0,1,n)
    body=x[:-n].copy(); body[:n]=head*w+tail*(1-w); return body

# --- footsteps (player): soft leather on stone
for i,(f,d) in enumerate([(95,0.05),(80,0.06)]):
    x=np.sin(2*np.pi*f*t(0.16))*env(0.16,0.004,d)*0.9+lp(noise(0.16),900)*env(0.16,0.002,0.03)*0.7
    write(f"step{i+1}",x,peak=0.7)

# --- demon step: heavy thud, then claws clicking on stone
thud=np.sin(2*np.pi*(52-18*t(0.4))*t(0.4))*env(0.4,0.006,0.11)+lp(noise(0.4),300)*env(0.4,0.004,0.06)*0.8
claw=hp(noise(0.06),2500)*env(0.06,0.001,0.012)
x=mix(thud, at(claw,0.07,0.45)*0.35, at(claw,0.11,0.45)*0.25, at(claw,0.16,0.45)*0.18)
write("demon_step",x)

# --- demon breathing loop: wet rasp in, rattle out
L=3.2; tt=t(L)
inh=np.clip(np.sin(np.pi*tt/1.2),0,None)*(tt<1.2)
exh=np.clip(np.sin(np.pi*(tt-1.5)/1.5),0,None)*((tt>1.5)&(tt<3.0))
x=bp(noise(L),500,1600)*inh*0.6+bp(noise(L),180,700)*exh*(0.6+0.4*np.sign(np.sin(2*np.pi*27*tt)))
x+=np.sin(2*np.pi*46*tt)*exh*0.25
write("demon_breath",x,loop=True,peak=0.8)

# --- demon scream: several detuned saws falling in pitch, torn up with noise
L=1.9; tt=t(L); x=np.zeros_like(tt)
for f0,det in [(520,1.0),(533,1.01),(790,0.99),(1010,1.02),(260,1.0)]:
    f=f0*det*(1.0+0.25*np.exp(-tt*5)-0.22*tt/L)*(1+0.03*np.sin(2*np.pi*31*tt))
    ph=2*np.pi*np.cumsum(f)/SR
    x+=2*((ph/(2*np.pi))%1)-1
x=x/5+bp(noise(L),900,4000)*0.5
x=np.tanh(x*3.5)*np.minimum(tt/0.03,1)*np.exp(-np.maximum(tt-1.1,0)/0.25)
write("demon_scream",x,peak=0.95)

# --- demon notice: short low growl
L=0.9; tt=t(L); f=68*(1+0.15*np.sin(2*np.pi*3*tt)); ph=np.cumsum(f)/SR
x=lp(2*(ph%1)-1,420)*(0.6+0.4*np.sin(2*np.pi*24*tt))*env(L,0.08,0.3)
write("demon_notice",x)

# --- heartbeat: lub-dub
lub=np.sin(2*np.pi*58*t(0.14))*env(0.14,0.008,0.035)
dub=np.sin(2*np.pi*72*t(0.12))*env(0.12,0.006,0.028)*0.75
write("heartbeat",lp(mix(at(lub,0,0.42),at(dub,0.2,0.42)),220))

# --- drone loop: frequencies are multiples of 1/8 Hz so 8 s loops exactly
L=8.0; tt=t(L); x=np.zeros_like(tt)
for f,a in [(41.0,1.0),(41.5,0.8),(61.75,0.5),(82.5,0.35),(123.25,0.15)]: x+=a*np.sin(2*np.pi*f*tt)
x+=seamless(np.concatenate([lp(noise(L+0.5),160)*1.2]),0.5)[:len(tt)]*0.6
write("drone",x,loop=True,peak=0.8)

# --- reversed choir loop (GDD: "perevernutyi tserkovnyi khor")
def choir(freqs,L,vib=5.2):
    tt=t(L); x=np.zeros_like(tt)
    for f in freqs:
        for det in (0.994,1.0,1.007):
            ph=2*np.pi*f*det*tt+0.06*np.sin(2*np.pi*vib*tt+rng.uniform(0,6))*f/100
            x+=np.sin(ph)+0.4*np.sin(2*ph)+0.2*np.sin(3*ph)
    return bp(x,250,2600)
L=7.0; tt=t(L)
x=choir([220.0,261.63,329.63,440.0],L)*np.sin(np.pi*tt/L)**1.5
x=x[::-1]*np.exp(-0*tt)
x=x*(1-np.exp(-tt*3))  # reversed swell
write("choir_rev",np.concatenate([x,np.zeros(int(SR*1.0))]),loop=True,peak=0.6)

# --- hit: bang, boom and a ringing ear
L=1.0; tt=t(L)
x=noise(L)*env(L,0.001,0.05)+np.sin(2*np.pi*(70-30*tt)*tt)*env(L,0.002,0.18)*1.2
x+=(np.sin(2*np.pi*2950*tt)+0.6*np.sin(2*np.pi*3110*tt))*env(L,0.01,0.35)*0.18
write("hit",np.tanh(x*2),peak=0.95)

# --- candle going out: a soft puff
write("candle_out",lp(noise(0.3),1400)*env(0.3,0.01,0.06),peak=0.5)

# --- pickup: small bell;  place: deep bell
def bell(f,L,d):
    tt=t(L); x=np.zeros_like(tt)
    for r,a,dd in [(1,1,1),(2.76,0.5,0.6),(5.4,0.25,0.35),(8.93,0.12,0.2)]: x+=a*np.sin(2*np.pi*f*r*tt)*np.exp(-tt/(d*dd))
    return x*np.minimum(tt/0.003,1)
write("pickup",bell(660,1.4,0.45),peak=0.6)
write("place",bell(147,3.0,1.1)+bell(220,3.0,0.8)*0.4,peak=0.85)

# --- burn: the unfinished line fizzling away
write("burn",hp(noise(0.5),3000)*env(0.5,0.01,0.14)*(0.6+0.4*rng.uniform(0,1,int(SR*0.5))),peak=0.5)

# --- banish: roar swallowed by a rising choir and a bell
L=3.6; tt=t(L)
x=bp(noise(L),200,3000)*np.exp(-tt/0.5)*1.2+choir([293.66,369.99,440.0,587.33],L)*np.minimum(tt/1.2,1)*np.exp(-np.maximum(tt-2.2,0)/0.5)*0.25
x=mix(x,at(bell(294,2.4,0.9),1.0,L)*1.5)
write("banish",x)

# --- door slam
L=1.0; tt=t(L)
x=np.sin(2*np.pi*(48-10*tt)*tt)*env(L,0.002,0.2)*1.3+lp(noise(L),1800)*env(L,0.001,0.04)+hp(noise(L),1500)*env(L,0.001,0.012)*0.5
write("door_slam",np.tanh(x*1.8),peak=0.95)

# --- candlestick falling: metal clatter that settles
L=1.3; x=np.zeros(int(SR*L)); when=0.0; gap=0.2
for k in range(7):
    f=rng.uniform(1400,2600); L2=0.35; tt2=t(L2)
    ping=(np.sin(2*np.pi*f*tt2)+0.6*np.sin(2*np.pi*f*1.51*tt2)+0.4*np.sin(2*np.pi*f*2.27*tt2))*np.exp(-tt2/0.05)+hp(noise(L2),3000)*np.exp(-tt2/0.008)
    x+=at(ping,when,L)*(0.9**k); when+=gap; gap*=0.72
write("clatter",x)

# --- swing: claws through the air
L=0.32; tt=t(L); n=noise(L); f=600+2600*tt/L
x=np.zeros_like(tt); 
for a,b in [(400,1200),(1200,2600)]: x+=bp(n,a,b)
write("swing",x*np.sin(np.pi*tt/L)**2,peak=0.6)

# --- ending: the choir the right way round, in a major chord
L=7.0; tt=t(L)
x=choir([196.0,246.94,293.66,392.0,587.33],L)*np.minimum(tt/2.5,1)*np.exp(-np.maximum(tt-5.0,0)/0.8)
write("ending",mix(x,at(bell(196,4.0,1.4),0.2,L)*8),peak=0.8)
