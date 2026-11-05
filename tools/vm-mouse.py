#!/usr/bin/python3
# Wirtualna mysz do testów: mouse.py "m 840 1040" "s 1" "l" "r" (m = ruch, l/r = klik, s = pauza)
import fcntl, os, struct, sys, time
W,H=1680,1050
UI_SET_EVBIT=0x40045564; UI_SET_KEYBIT=0x40045565; UI_SET_ABSBIT=0x40045567; UI_DEV_CREATE=0x5501; UI_DEV_DESTROY=0x5502
EV_SYN,EV_KEY,EV_ABS=0,1,3; BTN_LEFT,BTN_RIGHT=0x110,0x111; ABS_X,ABS_Y=0,1
fd=os.open('/dev/uinput',os.O_WRONLY|os.O_NONBLOCK)
for e in (EV_KEY,EV_ABS): fcntl.ioctl(fd,UI_SET_EVBIT,e)
for k in (BTN_LEFT,BTN_RIGHT): fcntl.ioctl(fd,UI_SET_KEYBIT,k)
for a in (ABS_X,ABS_Y): fcntl.ioctl(fd,UI_SET_ABSBIT,a)
name=b'aster-test-mouse'.ljust(80,b'\0')
absmax=[0]*64; absmax[0]=absmax[1]=32767
dev=name+struct.pack('<HHHHI',3,1,1,1,0)+struct.pack('<64i',*absmax)+struct.pack('<64i',*[0]*64)*3
os.write(fd,dev); fcntl.ioctl(fd,UI_DEV_CREATE); time.sleep(1.2)
def ev(t,c,v): os.write(fd,struct.pack('<qqHHi',0,0,t,c,v))
def syn(): ev(EV_SYN,0,0)
def move(x,y): ev(EV_ABS,ABS_X,int(x*32767/(W-1))); ev(EV_ABS,ABS_Y,int(y*32767/(H-1))); syn()
pos=[840,500]
def glide(x,y):
    for i in range(1,13):
        move(pos[0]+(x-pos[0])*i/12,pos[1]+(y-pos[1])*i/12); time.sleep(0.015)
    pos[0],pos[1]=x,y
def click(b):
    ev(EV_KEY,b,1); syn(); time.sleep(0.05); ev(EV_KEY,b,0); syn()
for c in sys.argv[1:]:
    p=c.split()
    if p[0]=='m': glide(int(p[1]),int(p[2]))
    elif p[0]=='l': click(BTN_LEFT)
    elif p[0]=='r': click(BTN_RIGHT)
    elif p[0]=='s': time.sleep(float(p[1]))
    time.sleep(0.05)
time.sleep(0.2); fcntl.ioctl(fd,UI_DEV_DESTROY); os.close(fd)
