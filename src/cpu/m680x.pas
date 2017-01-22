unit m680x;

interface
uses {$IFDEF WINDOWS}windows,{$ENDIF}
     main_engine,dialogs,sysutils,timer_engine,vars_hide,cpu_misc;

const
  CPU_M6801=1;
  CPU_M6803=3;
  CPU_HD63701=10;

type
        band_m6800=record
                h,i,n,z,v,c:boolean;
        end;
        reg_m6800=record
                pc,sp:word;
                cc:band_m6800;
                d:parejas680X;
                wai:boolean;
                x:word;
        end;
        preg_m6800=^reg_m6800;
        cpu_m6800=class(cpu_class)
              constructor create(clock:dword;frames_div:word;tipo_cpu:byte);
              destructor Free;
            public
              internal_ram:array[0..$ff] of byte;
              procedure run(maximo:single);
              procedure reset;
              procedure change_io_calls(in_port1,in_port2,in_port3,in_port4:cpu_inport_call;out_port1,out_port2,out_port3,out_port4:cpu_outport_call);
              //M6803
              function m6803_internal_reg_r(direccion:word):byte;
              procedure m6803_internal_reg_w(direccion:word;valor:byte);
            private
              r:preg_m6800;
              in_port1,in_port2,in_port3,in_port4:cpu_inport_call;
              out_port1,out_port2,out_port3,out_port4:cpu_outport_call;
              port1_ddr,port2_ddr,port3_ddr,port4_ddr:byte;
              port1_data,port2_data,port3_data,port4_data:byte;
              ram_ctrl,trcsr,tdr,tcsr,tipo_cpu,latch09,pending_tcsr:byte;
              timer_next:longword;
              ctd,ocd:dparejas;
              tx:integer;
              trcsr_read:boolean;
              estados_t:array[0..$ff] of byte;
              procedure putword(direccion:word;valor:word);
              function getword(direccion:word):word;
              procedure pushw(reg:word);
              function popw:word;
              procedure pushb(reg:byte);
              function popb:byte;
              procedure poner_band(valor:byte);
              function coger_band:byte;
              function call_int(dir:word):byte;
              procedure MODIFIED_counters;
              procedure check_timer_event;
              //Opcodes
              function neg8(valor:byte):byte;
              function com8(valor:byte):byte;
              function lsr8(valor:byte):byte;
              function asl8(valor:byte):byte;
              function rol8(valor:byte):byte;
              function dec8(valor:byte):byte;
              function inc8(valor:byte):byte;
              procedure tst8(valor:byte);
              function ror8(valor:byte):byte;
              function sub8(valor1,valor2:byte):byte;
              function sbc8(valor1,valor2:byte):byte;
              function and8(valor1,valor2:byte):byte;
              function eor8(valor1,valor2:byte):byte;
              function adc8(valor1,valor2:byte):byte;
              function or8(valor1,valor2:byte):byte;
              function add8(valor1,valor2:byte):byte;
        end;

var
  m6800_0:cpu_m6800;

implementation
const

  //E8 95 E9
  direc_680x:array[0..$ff] of byte=(
 //   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
     $f,$f,$f,$f, 0, 0, 0,$f, 0, 0,$f,$f, 0, 0, 0, 0,  //00
      0, 0, 0, 0,$f,$f, 0, 0, 0, 0,$f, 0,$f,$f,$f,$f,  //10
      1,$f,$f, 1, 1,$1, 1, 1,$f,$f, 1, 1,$f, 1, 1,$f,  //20
     $f, 0, 0, 0, 0,$f, 0, 0, 0, 0, 0, 0, 0, 0,$f,$f,  //30
      0,$f,$f, 0, 0,$f,$f,$f, 0, 0, 0,$f, 0, 0,$f, 0,  //40
      0,$f,$f, 0, 0,$f,$f,$f, 0, 0, 0,$f, 0, 0,$f, 0,  //50
 //   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
     $f, 1, 1,$f, 6,$f, 6,$f,$f,$f, 6, 1, 6, 6, 4, 4,  //60
     $f, 1, 1, 8, 8,$f,$f,$f, 8,$f, 8,$f, 8, 8, 3, 3,  //70
 //   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
      1, 1, 1, 2, 1,$f, 1,$f, 1, 1, 1, 1, 2, 1, 2,$f,  //80
      5, 5,$f,$a, 5, 5, 5,$b, 5,$f, 5, 5,$a,$f,$f,$f,  //90
      6, 6,$f, 9, 6,$f, 6, 4,$f,$f, 6, 6,$f, 4, 9,$f,  //a0
     $f, 8,$f, 7,$f,$f, 8, 3,$f,$f, 8, 8,$f, 3,$f,$f,  //b0
 //   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
      1, 1,$f, 2, 1, 1, 1,$f, 1,$f, 1, 1, 2,$f, 2,$f,  //c0
     $f, 5,$f,$a, 5,$f, 5,$b,$f,$f, 5, 5,$a,$b,$a,$b,  //d0
     $f, 4,$f, 9, 6,$f, 6, 4, 4, 4, 6, 6, 9, 4, 9,$f,  //e0
     $f,$f,$f, 7,$f,$f, 8, 3,$f,$f,$f,$f, 7, 3, 7, 3); //f0

  ciclos_6803:array[0..$ff] of byte=(
    	 // 0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F
	       99, 2,99,99, 3, 3, 2, 2, 3, 3, 2, 2, 2, 2, 2, 2,
	        2, 2,99,99,99,99, 2, 2,99, 2,99, 2,99,99,99,99,
	        3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
	        3, 3, 4, 4, 3, 3, 3, 3, 5, 5, 3,10, 4,10, 9,12,
	        2,99,99, 2, 2,99, 2, 2, 2, 2, 2,99, 2, 2,99, 2,
	        2,99,99, 2, 2,99, 2, 2, 2, 2, 2,99, 2, 2,99, 2,
	        6,99,99, 6, 6,99, 6, 6, 6, 6, 6,99, 6, 6, 3, 6,
	        6,99,99, 6, 6,99, 6, 6, 6, 6, 6,99, 6, 6, 3, 6,
	        2, 2, 2, 4, 2, 2, 2,99, 2, 2, 2, 2, 4, 6, 3,99,
	        3, 3, 3, 5, 3, 3, 3, 3, 3, 3, 3, 3, 5, 5, 4, 4,
	        4, 4, 4, 6, 4, 4, 4, 4, 4, 4, 4, 4, 6, 6, 5, 5,
	        4, 4, 4, 6, 4, 4, 4, 4, 4, 4, 4, 4, 6, 6, 5, 5,
	        2, 2, 2, 4, 2, 2, 2,99, 2, 2, 2, 2, 3,99, 3,99,
	        3, 3, 3, 5, 3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4,
	        4, 4, 4, 6, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5,
	        4, 4, 4, 6, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5);

  ciclos_63701:array[0..$ff] of byte=(
    	 // 0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F
	       99, 1,99,99, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
	        1, 1,99,99,99,99, 1, 1, 2, 2, 4, 1,99,99,99,99,
	        3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
          1, 1, 3, 3, 1, 1, 4, 4, 4, 5, 1,10, 5, 7, 9,12,
          1,99,99, 1, 1,99, 1, 1, 1, 1, 1,99, 1, 1,99, 1,
          1,99,99, 1, 1,99, 1, 1, 1, 1, 1,99, 1, 1,99, 1,
          6, 7, 7, 6, 6, 7, 6, 6, 6, 6, 6, 5, 6, 4, 3, 5,
          6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 4, 6, 4, 3, 5,
          2, 2, 2, 3, 2, 2, 2,99, 2, 2, 2, 2, 3, 5, 3,99,
          3, 3, 3, 4, 3, 3, 3, 3, 3, 3, 3, 3, 4, 5, 4, 4,
          4, 4, 4, 5, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5,
          4, 4, 4, 5, 4, 4, 4, 4, 4, 4, 4, 4, 5, 6, 5, 5,
          2, 2, 2, 3, 2, 2, 2,99, 2, 2, 2, 2, 3,99, 3,99,
          3, 3, 3, 4, 3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4,
          4, 4, 4, 5, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5,
          4, 4, 4, 5, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5);

  M6800_TRCSR_RDRF=$80; // Receive Data Register Full
  M6800_TRCSR_ORFE=$40; // Over Run Framing Error
  M6800_TRCSR_TDRE=$20; // Transmit Data Register Empty
  M6800_TRCSR_RIE=$10; // Receive Interrupt Enable
  M6800_TRCSR_RE=$08; // Receive Enable
  M6800_TRCSR_TIE=$04; // Transmit Interrupt Enable
  M6800_TRCSR_TE=$02; // Transmit Enable
  M6800_TRCSR_WU=$01; // Wake Up

  TCSR_OLVL=$01;
  TCSR_IEDG=$02;
  TCSR_ETOI=$04;
  TCSR_EOCI=$08;
  TCSR_EICI=$10;
  TCSR_TOF=$20;
  TCSR_OCF=$40;
  TCSR_ICF=$80;

function cpu_m6800.neg8(valor:byte):byte;
var
  tempw:word;
begin
   tempw:=-valor;
   r.cc.z:=((tempw and $ff)=0);
   r.cc.n:=(tempw and $80)<>0;
   r.cc.c:=(tempw and $100)<>0;
   r.cc.v:=((0 xor valor xor tempw xor (tempw shr 1)) and $80)<>0;
   neg8:=tempw;
end;

function cpu_m6800.com8(valor:byte):byte;
var
  tempb:byte;
begin
   tempb:=not(valor);
   r.cc.v:=false;
   r.cc.c:=true;
   r.cc.n:=(tempb and $80)<>0;
   r.cc.z:=(tempb=0);
   com8:=tempb;
end;

function cpu_m6800.lsr8(valor:byte):byte;
var
   tempb:byte;
begin
   tempb:=valor shr 1;
   r.cc.n:=false;
   r.cc.c:=(valor and 1)<>0;
   r.cc.z:=(tempb=0);
   lsr8:=tempb;
end;

function cpu_m6800.asl8(valor:byte):byte;
var
   tempw:word;
begin
   tempw:=valor shl 1;
   r.cc.z:=((tempw and $ff)=0);
   r.cc.c:=(tempw and $100)<>0;
   r.cc.n:=(tempw and $80)<>0;
   r.cc.v:=((valor xor valor xor tempw xor (tempw shr 1)) and $80)<>0;
   asl8:=tempw;
end;

function cpu_m6800.rol8(valor:byte):byte;
var
   tempw:word;
begin
   tempw:=(valor shl 1) or byte(r.cc.c);
   r.cc.z:=((tempw and $ff)=0);
   r.cc.c:=(tempw and $100)<>0;
   r.cc.n:=(tempw and $80)<>0;
   r.cc.v:=((valor xor valor xor tempw xor (tempw shr 1)) and $80)<>0;
   rol8:=tempw;
end;

function cpu_m6800.dec8(valor:byte):byte;
var
   tempb:byte;
begin
   tempb:=valor-1;
   r.cc.z:=(tempb=0);
   r.cc.n:=(tempb and $80)<>0;
   r.cc.v:=(tempb=$7f);
   dec8:=tempb;
end;

function cpu_m6800.inc8(valor:byte):byte;
var
   tempb:byte;
begin
   tempb:=valor+1;
   r.cc.z:=(tempb=0);
   r.cc.n:=(tempb and $80)<>0;
   r.cc.v:=(tempb=$80);
   inc8:=tempb;
end;

procedure cpu_m6800.tst8(valor:byte);
begin
   r.cc.v:=false;
   r.cc.c:=false;
   r.cc.z:=(valor=0);
   r.cc.n:=(valor and $80)<>0;
end;

function cpu_m6800.ror8(valor:byte):byte;
var
   tempb:byte;
begin
   tempb:=(valor shr 1) or (byte(r.cc.c) shl 7);
   r.cc.c:=(valor and $1)<>0;
   r.cc.z:=(tempb=0);
   r.cc.n:=(tempb and $80)<>0;
   ror8:=tempb;
end;

function cpu_m6800.sub8(valor1,valor2:byte):byte;
var
   tempw:word;
begin
   tempw:=valor1-valor2;
   r.cc.z:=((tempw and $ff)=0);
   r.cc.n:=(tempw and $80)<>0;
   r.cc.c:=(tempw and $100)<>0;
   r.cc.v:=((valor1 xor valor2 xor tempw xor (tempw shr 1)) and $80)<>0;
   sub8:=tempw;
end;

function cpu_m6800.sbc8(valor1,valor2:byte):byte;
var
   tempw:word;
begin
   tempw:=valor1-valor2-byte(r.cc.c);
   r.cc.z:=((tempw and $ff)=0);
   r.cc.n:=(tempw and $80)<>0;
   r.cc.c:=(tempw and $100)<>0;
   r.cc.v:=((valor1 xor valor2 xor tempw xor (tempw shr 1)) and $80)<>0;
   sbc8:=tempw;
end;

function cpu_m6800.and8(valor1,valor2:byte):byte;
var
  tempb:byte;
begin
  tempb:=valor1 and valor2;
  r.cc.v:=false;
  r.cc.z:=(tempb=0);
  r.cc.n:=(tempb and $80)<>0;
  and8:=tempb;
end;

function cpu_m6800.eor8(valor1,valor2:byte):byte;
var
  tempb:byte;
begin
  tempb:=valor1 xor valor2;
  r.cc.v:=false;
  r.cc.z:=(tempb=0);
  r.cc.n:=(tempb and $80)<>0;
  eor8:=tempb;
end;

function cpu_m6800.adc8(valor1,valor2:byte):byte;
var
  tempw:word;
begin
  tempw:=valor1+valor2+byte(r.cc.c);
  r.cc.n:=(tempw and $80)<>0;
  r.cc.z:=((tempw and $ff)=0);
  r.cc.c:=(tempw and $100)<>0;
  r.cc.v:=((valor1 xor valor2 xor tempw xor (tempw shr 1)) and $80)<>0;
  r.cc.h:=((valor1 xor valor2 xor tempw) and $10)<>0;
  adc8:=tempw;
end;

function cpu_m6800.or8(valor1,valor2:byte):byte;
var
  tempb:byte;
begin
  tempb:=valor1 or valor2;
  r.cc.v:=false;
  r.cc.z:=(tempb=0);
  r.cc.n:=(tempb and $80)<>0;
  or8:=tempb;
end;

function cpu_m6800.add8(valor1,valor2:byte):byte;
var
  tempw:word;
begin
  tempw:=valor1+valor2;
  r.cc.n:=(tempw and $80)<>0;
  r.cc.z:=((tempw and $ff)=0);
  r.cc.c:=(tempw and $100)<>0;
  r.cc.v:=((valor1 xor valor2 xor tempw xor (tempw shr 1)) and $80)<>0;
  r.cc.h:=((valor1 xor valor2 xor tempw) and $10)<>0;
  add8:=tempw;
end;

constructor cpu_m6800.create(clock:dword;frames_div:word;tipo_cpu:byte);
begin
getmem(self.r,sizeof(reg_m6800));
fillchar(self.r^,sizeof(reg_m6800),0);
self.numero_cpu:=cpu_main_init(clock div 4);
self.clock:=clock div 4;
self.tipo_cpu:=tipo_cpu;
case tipo_cpu of
  cpu_m6801,cpu_m6803:copymemory(@estados_t[0],@ciclos_6803[0],$100);
  cpu_hd63701:copymemory(@estados_t[0],@ciclos_63701[0],$100);
    else MessageDlg('Tipo M680X desconocido', mtInformation,[mbOk], 0)
end;
self.tframes:=(clock/4/frames_div)/llamadas_maquina.fps_max;
self.out_port1:=nil;
self.out_port2:=nil;
self.out_port3:=nil;
self.out_port4:=nil;
self.in_port1:=nil;
self.in_port2:=nil;
self.in_port3:=nil;
self.in_port4:=nil;
end;

destructor cpu_m6800.free;
begin
freemem(self.r);
end;

procedure cpu_m6800.reset;
begin
r.pc:=self.getword($FFFE);
r.x:=0;
r.d.a:=0;
r.d.b:=0;
r.sp:=0;
r.cc.h:=false;
r.cc.n:=false;
r.cc.z:=false;
r.cc.v:=false;
r.cc.c:=false;
r.cc.i:=true;
self.change_nmi(CLEAR_LINE);
self.change_irq(CLEAR_LINE);
self.change_reset(CLEAR_LINE);
r.wai:=false;
self.port1_ddr:=0;
self.port2_ddr:=0;
self.port3_ddr:=0;
self.port4_ddr:=0;
self.tcsr:=0;
self.ram_ctrl:=$40;
self.tcsr:=M6800_TRCSR_TDRE;
self.ctd.l:=0;
self.ocd.l:=$ffff;
self.trcsr_read:=false;
self.pending_tcsr:=0;
end;

procedure cpu_m6800.change_io_calls(in_port1,in_port2,in_port3,in_port4:cpu_inport_call;out_port1,out_port2,out_port3,out_port4:cpu_outport_call);
begin
  self.in_port1:=in_port1;
  self.in_port2:=in_port2;
  self.in_port3:=in_port3;
  self.in_port4:=in_port4;
  self.out_port1:=out_port1;
  self.out_port2:=out_port2;
  self.out_port3:=out_port3;
  self.out_port4:=out_port4;
end;

procedure cpu_m6800.putword(direccion:word;valor:word);
begin
self.putbyte(direccion,valor shr 8);
self.putbyte(direccion+1,valor and $FF);
end;

function cpu_m6800.getword(direccion:word):word;
var
  valor:byte;
begin
valor:=self.getbyte(direccion);
getword:=(valor shl 8)+(self.getbyte(direccion+1));
end;

procedure cpu_m6800.pushw(reg:word);
begin
self.putbyte(r.sp,reg and $FF);
r.sp:=r.sp-1;
self.putbyte(r.sp,(reg shr 8));
r.sp:=r.sp-1;
end;

function cpu_m6800.popw:word;
var
  temp:byte;
begin
r.sp:=r.sp+1;
temp:=self.getbyte(r.sp);
r.sp:=r.sp+1;
popw:=(temp shl 8) or self.getbyte(r.sp);
end;

procedure cpu_m6800.pushb(reg:byte);
begin
self.putbyte(r.sp,reg);
r.sp:=r.sp-1;
end;

function cpu_m6800.popb:byte;
begin
r.sp:=r.sp+1;
popb:=self.getbyte(r.sp);
end;

procedure cpu_m6800.poner_band(valor:byte);
begin
r.cc.c:=(valor and 1)<>0;
r.cc.v:=(valor and 2)<>0;
r.cc.z:=(valor and 4)<>0;
r.cc.n:=(valor and 8)<>0;
r.cc.i:=(valor and $10)<>0;
r.cc.h:=(valor and $20)<>0;
end;

function cpu_m6800.coger_band:byte;
var
  temp:byte;
begin
temp:=byte(r.cc.c);
temp:=temp or (byte(r.cc.v) shl 1);
temp:=temp or (byte(r.cc.z) shl 2);
temp:=temp or (byte(r.cc.n) shl 3);
temp:=temp or (byte(r.cc.v) shl 4);;
coger_band:=temp or (byte(r.cc.v) shl 5);;
end;

//OCI -> fff4
//NMI -> fffc
//IRQ -> fff8
function cpu_m6800.call_int(dir:word):byte;
begin
  self.pushw(r.pc);
	self.pushw(r.x);
	self.pushb(r.d.a);
	self.pushb(r.d.b);
	self.pushb(self.coger_band);
  call_int:=12;
  r.cc.i:=true;
  r.pc:=self.getword(dir);
end;

procedure cpu_m6800.MODIFIED_counters;
begin
  if self.ocd.wl>=self.ctd.wl then self.ocd.wh:=self.ctd.wh
  else self.ocd.wh:=self.ctd.wh+1;
  //timer_next = (OCD - r.cdt < TOD - CTD) ? OCD : TOD;
  self.timer_next:=self.ocd.l;
end;

function cpu_m6800.m6803_internal_reg_r(direccion:word):byte;
var
  ret:byte;
begin
case direccion of
  $00:ret:=self.port1_ddr;
  $01:ret:=self.port2_ddr;
  $02:if @self.in_port1<>nil then ret:=(self.in_port1 and (self.port1_ddr xor $ff)) or (self.port1_data and self.port1_ddr);
  $03:if @self.in_port2<>nil then ret:=(self.in_port2 and (self.port2_ddr xor $ff)) or (self.port2_data and self.port2_ddr);
  $04:ret:=self.port3_ddr;
  $05:ret:=self.port4_ddr;
  $06:if @self.in_port3<>nil then ret:=(self.in_port3 and (self.port3_ddr xor $ff)) or (self.port3_data and self.port3_ddr);
  $07:if @self.in_port4<>nil then ret:=(self.in_port4 and (self.port4_ddr xor $ff)) or (self.port4_data and self.port4_ddr);
  $08:begin
        ret:=self.tcsr;
        self.pending_tcsr:=0;
      end;
  $0b:begin
			  if (self.pending_tcsr and TCSR_OCF)=0 then self.tcsr:=self.tcsr and not(TCSR_OCF);
  			ret:=self.ocd.h0;
      end;
  $0c:begin
			  if (self.pending_tcsr and TCSR_OCF)=0 then self.tcsr:=self.tcsr and not(TCSR_OCF);
  			ret:=self.ocd.l0;
      end;
  $11:begin
			  self.trcsr_read:=true;
			  ret:=self.trcsr;
      end;
  $14:ret:=self.ram_ctrl;
  $40..$ff:ret:=self.internal_ram[direccion];
    else MessageDlg('Read Port 680X desconocido. Port='+inttohex(direccion,2), mtInformation,[mbOk], 0)
end;
m6803_internal_reg_r:=ret;
end;

procedure cpu_m6800.m6803_internal_reg_w(direccion:word;valor:byte);
begin
self.internal_ram[direccion]:=valor;
case direccion of
  $00:if (self.port1_ddr<>valor) then begin
				self.port1_ddr:=valor;
				if (self.port1_ddr=$ff) then	begin
          if @self.out_port1<>nil then self.out_port1(self.port1_data);
        end else begin
          if @self.out_port1<>nil then self.out_port1((self.port1_data and self.port1_ddr) or (self.in_port1 and (self.port1_ddr xor $ff)));
        end;
      end;
  $01:if (self.port2_ddr<>valor) then begin
        self.port2_ddr:=valor;
				if (self.port2_ddr=$ff) then	begin
          if @self.out_port2<>nil then self.out_port2(self.port2_data);
        end else begin
          if @self.out_port2<>nil then self.out_port2((self.port2_data and self.port2_ddr) or (self.in_port2 and (self.port2_ddr xor $ff)));
        end;
			end;
  $02:begin
  			self.port1_data:=valor;
  			if (self.port1_ddr=$ff) then begin
	  			if @self.out_port1<>nil then self.out_port1(self.port1_data);
  			end else begin
          if @self.out_port1<>nil then self.out_port1((self.port1_data and self.port1_ddr) or (self.in_port1 and (self.port1_ddr xor $ff)));
        end;
      end;
  $03:begin
	  		if (self.trcsr and M6800_TRCSR_TE)<>0 then begin
		  		self.port2_data:=(valor and $ef) or (self.tx shl 4);
			  end else begin
				  self.port2_data:=valor;
  			end;
	  		if (self.port2_ddr=$ff) then	begin
            if @self.out_port2<>nil then self.out_port2(self.port2_data);
          end else begin
            if @self.out_port2<>nil then self.out_port2((self.port2_data and self.port2_ddr) or (self.in_port2 and (self.port2_ddr xor $ff)));
          end;
      end;
  $04:if (self.port3_ddr<>valor) then begin
				self.port3_ddr:=valor;
				if (self.port3_ddr=$ff) then	begin
          if @self.out_port3<>nil then self.out_port3(self.port3_data);
        end else begin
          if @self.out_port3<>nil then self.out_port3((self.port3_data and self.port3_ddr) or (self.in_port3 and (self.port3_ddr xor $ff)));
        end;
      end;
  $05:if (self.port4_ddr<>valor) then begin
        self.port4_ddr:=valor;
				if (self.port4_ddr=$ff) then	begin
          if @self.out_port4<>nil then self.out_port4(self.port4_data);
        end else begin
          if @self.out_port4<>nil then self.out_port4((self.port4_data and self.port4_ddr) or (self.in_port4 and (self.port4_ddr xor $ff)));
        end;
			end;
  $06:begin
  			self.port3_data:=valor;
  			if (self.port3_ddr=$ff) then begin
	  			if @self.out_port3<>nil then self.out_port3(self.port3_data);
  			end else begin
          if @self.out_port3<>nil then self.out_port3((self.port3_data and self.port3_ddr) or (self.in_port3 and (self.port3_ddr xor $ff)));
        end;
      end;
  $07:begin
	  		if (self.trcsr and M6800_TRCSR_TE)<>0 then begin
		  		self.port4_data:=(valor and $ef) or (self.tx shl 4);
			  end else begin
				  self.port4_data:=valor;
  			end;
	  		if (self.port4_ddr=$ff) then	begin
            if @self.out_port4<>nil then self.out_port4(self.port4_data);
          end else begin
            if @self.out_port4<>nil then self.out_port4((self.port4_data and self.port4_ddr) or (self.in_port4 and (self.port4_ddr xor $ff)));
          end;
      end;
  $08:begin
        self.tcsr:=valor;
        self.pending_tcsr:=self.pending_tcsr and self.tcsr;
        if not(r.cc.i) then if ((self.tcsr and (TCSR_EOCI or TCSR_OCF))=(TCSR_EOCI or TCSR_OCF)) then call_int($fff4);
      end;
  $09:begin
			  self.latch09:=valor;	// 6301 only */
  			self.ctd.wl:=$fff8;
  			//TOH = CTH;
  			self.MODIFIED_counters;
			end;
	$0a:begin	// 6301 only */
  			self.ctd.wl:=(self.latch09 shl 8)+valor;
  			//TOH = CTH;
  			self.MODIFIED_counters;
      end;
  $0b:if self.ocd.h0<>valor then begin
   			self.ocd.h0:=valor;
  			self.MODIFIED_counters;
			end;
  $0c:if self.ocd.l0<>valor then begin
  			self.ocd.l0:=valor;
  			self.MODIFIED_counters;
			end;
  $11:self.trcsr:=(self.trcsr and $e0) or (valor and $1f);
  $13:begin
        if self.trcsr_read then begin
  				self.trcsr_read:=false;
  				self.trcsr:=self.trcsr and not(M6800_TRCSR_TDRE);
			  end;
			  self.tdr:=valor;
      end;
  $14:self.ram_ctrl:=valor;
  $12,$15,$40..$ff:exit;
  else MessageDlg('Write Port 680X desconocido. Port='+inttohex(direccion,2)+' PC='+inttohex(r.pc,10), mtInformation,[mbOk], 0)
end;
end;

procedure cpu_m6800.check_timer_event;
begin
	// OCI */
	if (self.ctd.l>=self.ocd.l) then begin
		self.ocd.wh:=self.ocd.wh+$1;	// next IRQ point
    self.pending_tcsr:=self.pending_tcsr or TCSR_OCF;
		self.tcsr:=self.tcsr or TCSR_OCF;
		//MODIFIED_tcsr;
		if (not(r.cc.i) and ((self.tcsr and TCSR_EOCI)<>0)) then self.call_int($fff4);
	end;
	// set next event */
	//timer_next = (OCD - r.cdt < TOD - CTD) ? OCD : TOD;
  self.timer_next:=self.ocd.l;
end;

procedure cpu_m6800.run(maximo:single);
var
  instruccion,numero,tempb,tempb2:byte;
  posicion,tempw,tempw2,numerow:word;
  templ:dword;
begin
self.contador:=0;
while self.contador<maximo do begin
if self.pedir_reset<>CLEAR_LINE then begin
  tempb:=self.pedir_reset;
  self.reset;
  if tempb=ASSERT_LINE then self.pedir_reset:=ASSERT_LINE;
  self.contador:=trunc(maximo);
  exit;
end;
if (self.pedir_halt<>CLEAR_LINE) then begin
  self.contador:=trunc(maximo);
  exit;
end;
self.estados_demas:=0;
//comprobar irq's
if (self.pedir_nmi<>CLEAR_LINE) then begin
  if self.nmi_state=CLEAR_LINE then self.estados_demas:=self.call_int($fffc);
  if self.pedir_nmi=PULSE_LINE then self.pedir_nmi:=CLEAR_LINE;
  if self.pedir_nmi=ASSERT_LINE then self.nmi_state:=ASSERT_LINE;
end else begin
  if ((self.pedir_irq<>CLEAR_LINE) and not(r.cc.i)) then begin
      self.pedir_irq:=CLEAR_LINE;
      self.estados_demas:=self.call_int($fff8);
  end else begin
      if not(r.cc.i) then if ((self.tcsr and (TCSR_EOCI or TCSR_OCF))=(TCSR_EOCI or TCSR_OCF)) then self.call_int($fff4);
  end;
end;
// CLEANUP_COUNTERS()
self.ocd.wh:=self.ocd.wh-self.ctd.wh;
self.ctd.wh:=0;
//timer_next = (OCD - r.cdt < TOD - CTD) ? OCD : TOD;
self.timer_next:=self.ocd.l;
self.opcode:=true;
instruccion:=self.getbyte(r.pc);
r.pc:=r.pc+1;
self.opcode:=false;
//tipo de direccionamiento
case direc_680x[instruccion] of
  0:; //inerente
  1:begin //IMMBYTE
      numero:=self.getbyte(r.pc);
      r.pc:=r.pc+1;
    end;
  2:begin  //IMMWORD
      numerow:=self.getword(r.pc);
      r.pc:=r.pc+2;
    end;
  3:begin //EXTENDED
      posicion:=self.getword(r.pc);
      r.pc:=r.pc+2;
    end;
  4:begin  //INDEXED
      posicion:=r.x+self.getbyte(r.pc);
      r.pc:=r.pc+1;
    end;
  5:begin  //DIRBYTE
      posicion:=self.getbyte(r.pc);
      r.pc:=r.pc+1;
      numero:=self.getbyte(posicion);
    end;
  6:begin //IDXBYTE
      posicion:=r.x+self.getbyte(r.pc);
      r.pc:=r.pc+1;
      numero:=self.getbyte(posicion);
    end;
  7:begin //EXTWORD
      posicion:=self.getword(r.pc);
      r.pc:=r.pc+2;
      numerow:=self.getword(posicion);
    end;
  8:begin   //EXTBYTE
      posicion:=self.getword(r.pc);
      r.pc:=r.pc+2;
      numero:=self.getbyte(posicion);
    end;
  9:begin   //IDXWORD
      posicion:=r.x+self.getbyte(r.pc);
      r.pc:=r.pc+1;
      numerow:=self.getword(posicion);
    end;
  $a:begin //DIRWORD
      posicion:=self.getbyte(r.pc);
      r.pc:=r.pc+1;
      numerow:=self.getword(posicion);
     end;
  $b:begin //DIRECT
      posicion:=self.getbyte(r.pc);
      r.pc:=r.pc+1;
     end;
 $f:MessageDlg('Instruccion M6800 '+inttohex(instruccion,2)+' desconocida. PC='+inttohex(r.pc-1,10), mtInformation,[mbOk], 0);
end;
case instruccion of
  $04:begin //lsrd
        r.cc.n:=false;
        r.cc.c:=(r.d.w and $1)<>0;
        r.d.w:=r.d.w shr 1;
        r.cc.z:=(r.d.w=0);
      end;
  $05:begin  //asld
        templ:=r.d.w shl 1;
        r.cc.n:=(templ and $8000)<>0;
        r.cc.z:=(templ=0);
        r.cc.c:=(templ and $10000)<>0;
        r.cc.v:=((r.d.w xor r.d.w xor templ xor (templ shr 1)) and $8000)<>0;
	r.d.w:=templ;
      end;
  $06:self.poner_band(r.d.a); //tap
  $08:begin  //inx
       r.x:=r.x+1;
       r.cc.z:=(r.x=0);
      end;
  $09:begin //dex
       r.x:=r.x-1;
       r.cc.z:=(r.x=0);
      end;
  $0c:r.cc.c:=false; //clc
  $0d:r.cc.c:=true; //sec
  $0e:r.cc.i:=false; //cli
  $0f:r.cc.i:=true; //sei
  $10:begin //sba
       tempw:=r.d.a-r.d.b;
	     r.cc.z:=((tempw and $ff)=0);
       r.cc.n:=(tempw and $80)<>0;
       r.cc.c:=(tempw and $100)<>0;
       r.cc.v:=((r.d.a xor r.d.b xor tempw xor (tempw shr 1)) and $80)<>0;
	     r.d.a:=tempw;
      end;
  $11:begin  //cba
       tempw:=r.d.a-r.d.b;
       r.cc.z:=((tempw and $ff)=0);
       r.cc.n:=(tempw and $80)<>0;
       r.cc.c:=(tempw and $100)<>0;
       r.cc.v:=((r.d.a xor r.d.b xor tempw xor (tempw shr 1)) and $80)<>0;
      end;
  $12,$13:r.x:=r.x+self.getbyte(r.sp+1); //undocumented asx1 y asx2
  $16:begin //tab
       r.d.b:=r.d.a;
       r.cc.v:=false;
       r.cc.z:=(r.d.b=0);
       r.cc.n:=(r.d.b and $80)<>0;
      end;
  $17:begin //tba
       r.d.a:=r.d.b;
       r.cc.v:=false;
       r.cc.z:=(r.d.a=0);
       r.cc.n:=(r.d.a and $80)<>0;
      end;
  $18:begin //XGDX 63701
       tempw:=r.x;
       r.x:=r.d.w;
       r.d.w:=tempw;
      end;
  $19:begin //daa
       tempb:=r.d.a and $f0;  //msn
       tempb2:=r.d.a and $f;  //lsn
       tempw:=0;  //cf
       if ((tempb2>$09) or r.cc.h) then tempw:=tempw or $06;
       if ((tempb>$80) and (tempb2>$09)) then tempw:=tempw or $60;
       if ((tempb>$90) or r.cc.c) then tempw:=tempw or $60;
       tempw2:=tempw+r.d.a;
       r.cc.z:=(tempw2 and $ff)=0;
       r.cc.n:=(tempw2 and $80)<>0;
       r.cc.c:=(tempw2 and $100)<>0;
       r.d.a:=tempw2;
      end;
  $1b:begin //aba
       tempw:=r.d.a+r.d.b;
       r.cc.z:=((tempw and $ff)=0);
       r.cc.c:=(tempw and $100)<>0;
       r.cc.n:=(tempw and $80)<>0;
       r.cc.v:=((r.d.a xor r.d.b xor tempw xor (tempw shr 1)) and $80)<>0;
       r.cc.h:=((r.d.a xor r.d.b xor tempw) and $10)<>0;
       r.d.a:=tempw;
      end;
  $20:r.pc:=r.pc+shortint(numero);
  $23:if (r.cc.c or r.cc.z) then r.pc:=r.pc+shortint(numero);  //bls
  $24:if not(r.cc.c) then r.pc:=r.pc+shortint(numero);  //bcc
  $25:if r.cc.c then r.pc:=r.pc+shortint(numero);  //bcs
  $26:if not(r.cc.z) then r.pc:=r.pc+shortint(numero);  //bne
  $27:if r.cc.z then r.pc:=r.pc+shortint(numero);  //beq
  $2a:if not(r.cc.n) then r.pc:=r.pc+shortint(numero);  //bpl
  $2b:if r.cc.n then r.pc:=r.pc+shortint(numero); //bmi
  $2d:if (r.cc.n xor r.cc.v) then r.pc:=r.pc+shortint(numero); //blt
  $2e:if not((r.cc.n xor r.cc.v) or r.cc.z) then r.pc:=r.pc+shortint(numero); //bgt
  $31:r.sp:=r.sp+1; //ins
  $32:r.d.a:=self.popb; //popa
  $33:r.d.b:=self.popb; //popb
  $34:r.sp:=r.sp-1; //des
  $36:self.pushb(r.d.a);  //psha
  $37:self.pushb(r.d.b);  //pshb
  $38:r.x:=self.popw;
  $39:r.pc:=self.popw; //rts
  $3a:r.x:=r.x+r.d.b;  //abx
  $3b:begin  //rti
        self.poner_band(self.popb);
        r.d.b:=self.popb;
        r.d.a:=self.popb;
        r.x:=self.popw;
        r.pc:=self.popw;
      end;
  $3c:self.pushw(r.x); //pshx
  $3d:begin //mul
        r.d.w:=r.d.a*r.d.b;
        r.cc.c:=(r.d.w and $80)<>0;
      end;
  $40:r.d.a:=self.neg8(r.d.a);  //nega
  $43:r.d.a:=self.com8(r.d.a);  //coma
  $44:r.d.a:=self.lsr8(r.d.a);  //lsra
  $48:r.d.a:=self.asl8(r.d.a); //asla
  $49:r.d.a:=self.rol8(r.d.a); //rola
  $4a:r.d.a:=self.dec8(r.d.a);  //deca
  $4c:r.d.a:=self.inc8(r.d.a);  //inca
  $4d:self.tst8(r.d.a);  //tsta
  $4f:begin  //clra
       r.d.a:=0;
       r.cc.z:=true;
       r.cc.n:=false;
       r.cc.v:=false;
       r.cc.c:=false;
      end;
  $50:r.d.b:=self.neg8(r.d.b); //negb
  $53:r.d.b:=self.com8(r.d.b); //comb
  $54:r.d.b:=self.lsr8(r.d.b); //lsrb
  $58:r.d.b:=self.asl8(r.d.b); //aslb
  $59:r.d.b:=self.rol8(r.d.b); //rolb
  $5a:r.d.b:=self.dec8(r.d.b); //decb
  $5c:r.d.b:=self.inc8(r.d.b); //incb
  $5d:self.tst8(r.d.b);  //tstb
  $5f:begin  //clrb
       r.d.b:=0;
       r.cc.z:=true;
       r.cc.n:=false;
       r.cc.v:=false;
       r.cc.c:=false;
      end;
  $61:begin  //aim_ix - HD63701YO
       tempw:=r.x+self.getbyte(r.pc);
       r.pc:=r.pc+1;
       tempb:=self.getbyte(tempw) and numero;
       r.cc.v:=false;
       r.cc.z:=(tempb=0);
       r.cc.n:=(tempb and $80)<>0;
       self.putbyte(tempw,tempb);
      end;
  $62:begin //OIM - HD63701YO
       tempw:=r.x+self.getbyte(r.pc);
       r.pc:=r.pc+1;
       tempb:=self.getbyte(tempw) or numero;
       r.cc.v:=false;
       r.cc.z:=(tempb=0);
       r.cc.n:=(tempb and $80)<>0;
       self.putbyte(tempw,tempb);
      end;
  $71:begin  //aim - HD63701YO
       tempw:=self.getbyte(r.pc);
       r.pc:=r.pc+1;
       tempb:=self.getbyte(tempw) and numero;
       r.cc.v:=false;
       r.cc.z:=(tempb=0);
       r.cc.n:=(tempb and $80)<>0;
       self.putbyte(tempw,tempb);
      end;
  $72:begin //oim - HD63701
       tempw:=self.getbyte(r.pc);
       r.pc:=r.pc+1;
       tempb:=self.getbyte(tempw) or numero;
       r.cc.v:=false;
       r.cc.z:=(tempb=0);
       r.cc.n:=(tempb and $80)<>0;
       self.putbyte(tempw,tempb);
      end;
  $73:begin //com
       tempb:=self.com8(numero);
       self.putbyte(posicion,tempb);
      end;
  $64,$74:begin  //lsr
       tempb:=self.lsr8(numero);
       self.putbyte(posicion,tempb);
      end;
  $66:begin //ror
       tempb:=self.ror8(numero);
       self.putbyte(posicion,tempb);
      end;
  $78:begin //asl
       tempb:=self.asl8(numero);
       self.putbyte(posicion,tempb);
      end;
  $6a,$7a:begin  //dec
       tempb:=self.dec8(numero);
       self.putbyte(posicion,tempb);
      end;
  $6b:begin  // TIM HD63701YO
       tempw:=r.x+self.getbyte(r.pc);
       r.pc:=r.pc+1;
       tempb:=self.getbyte(tempw) and numero;
       r.cc.v:=false;
       r.cc.z:=(tempb=0);
       r.cc.n:=(tempb and $80)<>0;
      end;
  $6c,$7c:begin //inc
       tempb:=self.inc8(numero);
       self.putbyte(posicion,tempb);
      end;
  $6d,$7d:self.tst8(numero);  //tst
  $6e,$7e:r.pc:=posicion; //jmp
  $6f,$7f:begin //clr
       self.putbyte(posicion,0);
       r.cc.z:=true;
       r.cc.n:=false;
       r.cc.v:=false;
       r.cc.c:=false;
      end;
  $80,$90,$a0:r.d.a:=self.sub8(r.d.a,numero);  //suba
  $81,$91,$a1,$b1:self.sub8(r.d.a,numero); //cmpa
  $82:r.d.a:=self.sbc8(r.d.a,numero);  //sbca
  $83,$93,$a3,$b3:begin //subd
       templ:=r.d.w-numerow;
       r.cc.z:=((templ and $ffff)=0);
       r.cc.n:=(templ and $8000)<>0;
       r.cc.c:=(templ and $10000)<>0;
       r.cc.v:=((r.d.w xor numerow xor templ xor (templ shr 1)) and $8000)<>0;
       r.d.w:=templ;
      end;
  $84,$94,$a4:r.d.a:=self.and8(r.d.a,numero); //anda
  $95:self.and8(r.d.a,numero); //bita
  $86,$96,$a6,$b6:begin //lda
       r.d.a:=numero;
       r.cc.v:=false;
       r.cc.z:=(numero=0);
       r.cc.n:=(numero and $80)<>0;
      end;
  $97,$a7,$b7:begin //sta
       r.cc.v:=false;
       r.cc.z:=(r.d.a=0);
       r.cc.n:=(r.d.a and $80)<>0;
       self.putbyte(posicion,r.d.a);
      end;
  $88,$98:r.d.a:=self.eor8(r.d.a,numero);  //eora
  $89:r.d.a:=self.adc8(r.d.a,numero);  //adca
  $8a,$9a,$aa,$ba:r.d.a:=self.or8(r.d.a,numero);  //ora
  $8b,$9b,$ab,$bb:r.d.a:=self.add8(r.d.a,numero);  //adda
  $8c,$9c:begin //cpmx solo 6801/03
       templ:=r.x-numerow;
       r.cc.z:=((templ and $ffff)=0);
       r.cc.n:=(templ and $8000)<>0;
       r.cc.v:=((r.x xor numerow xor templ xor (templ shr 1)) and $8000)<>0;
       if self.tipo_cpu=CPU_M6803 then r.cc.c:=(templ and $10000)<>0;
      end;
  $8d:begin //bsr
       self.pushw(r.pc);
       r.pc:=r.pc+shortint(numero);
      end;
  $ad,$bd:begin  //jsr
       self.pushw(r.pc);
       r.pc:=posicion;
      end;
  $8e,$ae:begin  //lds
       r.sp:=numerow;
       r.cc.v:=false;
       r.cc.z:=(numerow=0);
       r.cc.n:=(numerow and $8000)<>0;
      end;
  $c0:r.d.b:=self.sub8(r.d.b,numero); //subb
  $c1,$d1,$e1:self.sub8(r.d.b,numero); //cmpb
  $c3,$d3,$e3,$f3:begin  //addd
       templ:=r.d.w+numerow;
       r.cc.z:=((templ and $ffff)=0);
       r.cc.n:=(templ and $8000)<>0;
       r.cc.c:=(templ and $10000)<>0;
       r.cc.v:=((r.d.w xor numerow xor templ xor (templ shr 1)) and $8000)<>0;
       r.d.w:=templ;
      end;
  $c4,$d4,$e4:r.d.b:=self.and8(r.d.b,numero); //andb
  $c5:self.and8(r.d.b,numero); //bitb
  $c6,$d6,$e6,$f6:begin //ldb
       r.d.b:=numero;
       r.cc.v:=false;
       r.cc.z:=(numero=0);
       r.cc.n:=(numero and $80)<>0;
      end;
  $d7,$e7,$f7:begin //stb
       r.cc.v:=false;
       r.cc.z:=(r.d.b=0);
       r.cc.n:=(r.d.b and $80)<>0;
       self.putbyte(posicion,r.d.b);
      end;
  $c8,$e8:r.d.b:=self.eor8(r.d.b,numero);  //eorb
  $e9:r.d.b:=self.adc8(r.d.b,numero);  //adcb
  $ca,$da,$ea:r.d.b:=self.or8(r.d.b,numero);  //orb
  $cb,$db,$eb:r.d.b:=self.add8(r.d.b,numero); //addb
  $cc,$dc,$ec,$fc:begin  //ldd 6803 Only
       r.d.w:=numerow;
       r.cc.v:=false;
       r.cc.z:=(numerow=0);
       r.cc.n:=(numerow and $8000)<>0;
      end;
  $dd,$ed,$fd:begin //std
       r.cc.v:=false;
       r.cc.z:=(r.d.w=0);
       r.cc.n:=(r.d.w and $8000)<>0;
       self.putword(posicion,r.d.w);
      end;
  $ce,$de,$ee,$fe:begin //ldx
       r.x:=numerow;
       r.cc.v:=false;
       r.cc.z:=(numerow=0);
       r.cc.n:=(numerow and $8000)<>0;
      end;
  $df,$ff:begin  //stx
       r.cc.v:=false;
       r.cc.z:=(r.x=0);
       r.cc.n:=(r.x and $8000)<>0;
       self.putword(posicion,r.x);
  end;
end; //del case
tempb:=estados_t[instruccion]+self.estados_demas;
self.contador:=self.contador+tempb;
update_timer(tempb,self.numero_cpu);
if self.tipo_cpu=cpu_hd63701 then begin
  self.ctd.l:=self.ctd.l+tempb;
  if (self.ctd.l>=self.timer_next) then self.check_timer_event;
end;
end; //del while!
end;

end.
