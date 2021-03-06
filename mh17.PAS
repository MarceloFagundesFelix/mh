10 dat X Y R
20 cpy R X
30 loop Y
40    inc R
50 end                                                                                                                                                                                                                                                                                                                                                                                                                                                                           2.  Cria Segmento de Dados e Tabela de Simbolos
   3.  Carrega programa na estrutura de execucao
   4.  Executa passo a passo

INSTRUCOES

Nesta implementacao, mudamos o procedimento Executa que era recursivo
(tail recursion) para uma versao iterativa mais eficiente.

Acrescentamos a possibilidade de incluir coment�rios na linha do cmd
}
uses Crt,dos;

const
  PathLength  = 65;                  {tamanho da string do caminho do arquivo}
  FIMLINC     = '$';                        {marca de fim de linha de comando}
  NUM_DOs     = 100;                             {numero de DO's num programa}
  NUM_Rotulos = 5000;                {limite de numero de rotulos no programa}
  INICOMENT   = '%';                    {marca para iniciar comentario inline}

type
  FileName     = string[PathLength];
  TLinCmd      = string[127];        {linha de comando tem ate 127 caracteres}
  Identif      = string[5];             {identificadores tem ate 5 caracteres}
  TMem         = array[1..1] of integer;{locacao referente a cada V do progr.}
  PMem         = ^TMem;          {ponteiro para segmento de dados do programa}
  TcmdS        = (DAT_,INC_,RES_,COP_,JUM_,DO_,OD_);{cmds da linguagem SIMPLE}
  TcmdI        = (IINC,IDEC,ICOP,IRES,IREG,NULL);     {acoes do interpretador}
  TAcaoCAbs    = record               {acao referente ao comando interpretado}
                   cmdI: TcmdI;       {c = IINC -> v1:=val(v1)+1 }
                   par1: integer;     {c = IDEC -> v1:=val(v1)-1 }
                   par2: integer;     {c = ICOP -> v1:=val(v2)   }
                 end;                 {c = IRES -> v1:=0         }
  TCmdAbstrato = record
                   rotu : integer;         {rotulo da linha do comando SIMPLE}
                   cond : integer;              {condicao para executar o cmd}
                   acao : TAcaoCAbs;
                   desv : integer;               {desvio de fluxo do programa}
                 end;
  TReg         = record
                    rot : integer;     {rotulo do DO identifica o registrador}
                    vR  : integer;
                 end;
  TRegs        = array[1..NUM_DOs] of TReg; {limite para numero de DO's : 100}
  TCod         = array[1..1] of TCmdAbstrato;
  PTCod        = ^TCod;
  TSimb        = array[1..1] of Identif;
  PTSimb       = ^TSimb;

  TPilhaDO     = array[1..25] of integer;
{ TPilhaDO     = ^TElePilha;}
  TElePilha    = record
                   rot:   integer;  {pilha guarda rotulos dos DO's do programa}
                   prx:   TPilhaDO; {prox. da pilha de rotulos de instr's DO}
                 end;

var
  SimpleFileName : FileName;
  SimpleFile     : text;
  ProgMaqVirtual : text;
  Debug          :boolean;             {liga a execu�ao passo a passo}

  MEM: PMem;                           {ponteiro para inicio da area de dados}
  LOC: PMem;                      {ponteiro para locacoes no bloco de memoria}
  NLOCS: integer;            {numero de locacoes no bloco e de simbolos na TS}
  TS  : PTSimb;                   {ponteiro para inicio da Tabela de Simbolos}
  PRG : PTCod;                   {ponteiro para o inicio do programa abstrato}
  CAbs: PTCod;                   {ponteiro para comandos abstratos do Interpr}
  NCabs:integer;
  DESVIOaberto: integer;         {rotulo instr. DO com desv faltando definir}
  REG : TRegs;                   {vetor de registros de controle de instr. DO}
                                 {REG[i].Rot = L sss REG[i].vR = n}
  NREGs : integer;               {numero de Registradores de Controle}
  PilhaDO : TPilhaDO;            {pilha para armazenar rotulo de retorno p/DO}
  Topo    : integer;             {topo da implementacao estatica}
  ch      : char;

{----------------------------------------------------------------------------}
function Open(var f:text; Name: Filename): boolean;
{Abre Arquivo e retorna resultado da opera��o}
begin
  Assign(f,Name);
  {$I-}
  Reset(f);
  {$I+}
  Open := IOResult = 0;
end { Open };

{----------------------------------------------------------------------------}
procedure OpenSimpleFile;
{Abre arquivo fonte SIMPLE}
var Resp : char;
begin
  if ParamCount = 0 then
  begin
     Write('Entre nome do arquivo fonte (*.mh) : ');
     Readln(SimpleFileName);
     Write('Liga passo a passo? (s/n) :');
     Readln(Resp);
     Debug := (Resp = 'S') or (Resp = 's');
  end
  else SimpleFileName := ParamStr(1);
  if ParamCount = 2 then {se tem outro parametro}
     Debug := (ParamStr(2) = 'd') or (ParamStr(2) = 'D');
  if (SimpleFileName = '') or not Open(SimpleFile,SimpleFileName) then
  begin
    Writeln('ERRO: Arquivo ', SimpleFileName, ' nao foi encontrado.');
    Halt(1);
  end;
end {OpenSimpleFile};

{----------------------------------------------------------------------------}
Procedure ErroSintatico(L:TLinCmd);
begin
   writeln(L);
   Halt;
end;

{----------------------------------------------------------------------------}
Procedure LeLinhaComando(var L:TLinCmd);
var c: char; FimCmd: boolean;
begin
   L := '';
   if eoln(SimpleFile)
   then ReadLn(SimpleFile);
   FimCmd:=false;
   while not eoln(SimpleFile) do
   begin
      read(SimpleFile,c);
      if (c=INICOMENT)      {acabou a linha de comando e iniciou comentario}
      then FimCmd:=true;
      if not FimCmd         {s� acumula na string a parte antes do % }
      then L:=L+c;
   end;
   L:=L+FIMLINC;            {toda Linha de Comando tem uma marca '$' no fim}
end;

{---------------------------------------------------------------------------}
Procedure PulaBrancos(L:TLinCmd; var p:byte);
begin
   while L[p] = ' ' do inc(p);
end;

{---------------------------------------------------------------------------}
function EhLetra(c:char):boolean;
begin
   EhLetra := (c in ['a'..'z', 'A'..'Z'])
end;

function EhDigito(c:char):boolean;
begin
   EhDigito := (c in ['0'..'9'])
end;

{---------------------------------------------------------------------------}
function FimLinCmd(L:TLinCmd; p:byte):boolean;
{verifica se acabou a linha de comando}
begin
   PulaBrancos(L,p);
   FimLinCmd := (L[p] = FIMLINC);
end;

{---------------------------------------------------------------------------}
Procedure ObtemRotulo(L:TLinCmd; var p:byte; var R:integer);
{Rotulos em programas SIMPLE sao valores inteiros}
var sR:string[10];
    tamR:byte;
    cod:integer;
begin
  PulaBrancos(L,p);
  sR:='';                                         {Rotulo da linha do comando}
  tamR:=0;
  while (EhDigito(L[p])) and (tamR<7) do {monta o rotulo ate 6 caracteres}
  begin
    sR:=sR+L[p];
    inc(p);
    inc(tamR);
  end;
  if tamR<6 then                                   {labels vao de 0 ate 99999}
  begin
    val(sR,R,cod);                           {guarda em R o Rotulo do comando}
    if cod<>0 then ErroSintatico(L);   {chamada a este proc termina o Interp.}
  end else ErroSintatico(L);
end;

{--------------------------------------------------------------------------}
function EhDat(s:Identif):boolean;
begin
   EhDat := (s[1]in['d','D'])and(s[2]in['a','A'])and(s[3]in['t','T']);
end;

{--------------------------------------------------------------------------}
function EhRes(s:Identif):boolean;
begin
   EhRes := (s[1]in['r','R'])and(s[2]in['s','S'])and(s[3]in['t','T']);
end;

{--------------------------------------------------------------------------}
function EhCop(s:Identif):boolean;
begin
   EhCop := (s[1]in['c','C'])and(s[2]in['p','P'])and(s[3]in['y','Y']);
end;

{--------------------------------------------------------------------------}
function EhInc(s:Identif):boolean;
begin
   EhInc := (s[1]in['i','I'])and(s[2]in['n','N'])and(s[3]in['c','C']);
end;

{--------------------------------------------------------------------------}
function EhDo(s:Identif):boolean;
begin
   EhDo := (s[1]in['l','L'])and(s[2]in['o','O'])and
                (s[3]in['o','O'])and(s[4]in['p','P']);
end;

{--------------------------------------------------------------------------}
function EhOd(s:Identif):boolean;
begin
   EhOd := (s[1]in['e','E'])and(s[2]in['n','N'])and(s[3]in['d','D']);
end;

{--------------------------------------------------------------------------}
function EhJum(s:Identif):boolean;
begin
   EhJum := (s[1]in['j','J'])and(s[2]in['u','U'])and(s[3]in['m','M']);
end;

{--------------------------------------------------------------------------}
Procedure ObtemCmd(L:TLinCmd; var p:byte; var C:TcmdS);
var sC :Identif;
begin
    PulaBrancos(L,p);
    sC:='';
    while EhLetra(L[p]) do
    begin
      sC := sC + L[p];
      inc(p);
    end;
    if EhDat(sC) then C:= DAT_ else
    if EhRes(sC) then C:= RES_ else
    if EhCop(sC) then C:= COP_ else
    if EhInc(sC) then C:= INC_ else
    if EhDo(sC)  then C:= DO_  else
    if EhOd(sC)  then C:= OD_  else
    if EhJum(sC) then C:= JUM_ else ErroSintatico(L);
end;

{----------------------------------------------------------------------------}
function LocacaoVarTS(V:Identif):integer;
{retorna endereco da Locacao correspondente aa variavel identificada por V}
{se V nao esta na TS, retorna 0}
var i: integer;
begin
   LocacaoVarTS := 0;
   if TS <> nil then                 {existe algum simbolo instalado na TS}
   begin
     i:=1;
     while (TS^[i] <> V) and (i <= NLOCS) do
       inc(i);
     if (i <= NLOCS) then          {percorreu a tabela e achou V instalada}
       LocacaoVarTS := i;
   end
end;

{---------------------------------------------------------------------------}
Procedure ObtemParm(L:TLinCmd; var p:byte; var Parm:integer);
{Retorna a locacao do parametro da linha de comando}
var Id:Identif; tamId:byte; cod:integer;
begin
  PulaBrancos(L,p);
  Id:='';                                              {parametro como string}
  tamId:=0;
  if EhLetra(L[p]) then                    {primeiro caracter eh a..z ou A..Z}
  begin
    Id:=Id+L[p];
    inc(p);
    inc(tamId);
  end
  else ErroSintatico('Primeiro caracter invalido:'+L);
  while EhLetra(L[p]) or EhDigito(L[p]) do     {monta o parm ate 5 caracteres}
  begin
    Id:=Id+L[p];
    inc(p);
    inc(tamId);
  end;
  if tamId<6 then                            {identificadores tem ate 5 chars}
  begin
    Parm := LocacaoVarTS(Id);
    if Parm=0 then ErroSintatico(L);   {chamada a este proc termina o Interp.}
  end else ErroSintatico(L);
end;

{----------------------------------------------------------------------------}
Procedure Parse(SCmd:TLinCmd; var Rot:integer; var Cmd:TcmdS;
                              var Parm1,Parm2:integer);
{Analisa a string contendo uma linha de comando SIMPLE e retorna:
 Rot: rotulo da instrucao
 Cmd: comando SIMPLE
 Parm1, Parm2: endereco ou valor dos parametros dependendo do cmd encontrado}
var S: string;  p: byte;
begin
  p:=1;                       {comeca a analise a partir do primeiro caracter}
  ObtemRotulo(SCmd,p,Rot);
  ObtemCmd(SCmd,p,Cmd);
  case Cmd of
    RES_: ObtemParm(SCmd,p,Parm1);
    INC_: ObtemParm(SCmd,p,Parm1);
    COP_: begin
             ObtemParm(SCmd,p,Parm1);
             ObtemParm(SCmd,p,Parm2);
          end;
    JUM_: ObtemRotulo(SCmd,p,Parm1); {poderia ser variavel? O que teriamos?}
    DO_ : ObtemParm(SCmd,p,Parm1);
    OD_ : begin end;
    DAT_: ;            {Depois das declaracoes nao deveria haver novos DAT?}
  end;
end;

{----------------------------------------------------------------------------}
procedure GeraReset(L:integer; P:integer);
{Carrega um comando RES do progr. abstrato a ser executado pelo Interpretador}
begin
   with PRG^[NCAbs] do
   begin
      rotu := L;
      cond := 0; {indica que nao ha registrador para ser comparado com 0}
      with acao do
      begin
         cmdI := IRES;
         par1 := P;
         par2 := 0;
      end;
      desv := 0; {indica que basta seguir a sequencia natural dos cmds}
   end;
end;
{----------------------------------------------------------------------------}
procedure GeraIncre(L:integer; P:integer);
{Carrega um comando INC do progr. abstrato a ser executado pelo Interpretador}
begin
   with PRG^[NCAbs] do
   begin
      rotu := L;
      cond := 0;
      with acao do
      begin
         cmdI := IINC;
         par1 := P;
         par2 := 0;
      end;
      desv := 0; {indica que basta seguir a sequencia natural dos cmds}
   end;
end;
{----------------------------------------------------------------------------}
procedure GeraCopy(L:integer; P1:integer; P2:integer);
{Carrega um comando COP do progr. abstrato a ser executado pelo Interpretador}
begin
   with PRG^[NCAbs] do
   begin
      rotu := L;
      cond := 0; {indica que nao ha locacao para ser comparada com 0}
      with acao do
      begin
         cmdI := ICOP;
         par1 := P1;
         par2 := P2;
      end;
      desv := 0; {indica que basta seguir a sequencia natural dos cmds}
   end;
end;
{----------------------------------------------------------------------------}
Procedure Empilha(L:integer; var T:integer);
begin
   inc(T);
   PilhaDO[T]:=L;
end;

Procedure Desempilha(var L:integer; var T:integer);
begin
   if T>0 then
   begin
     L := PilhaDO[T];
     dec(T);
   end
   else
     ErroSintatico('OD nao fecha com DO');
end;

{----------------------------------------------------------------------------}
procedure GeraDo(L:integer; P:integer);
{Carrega um comando DO do progr. abstrato a ser executado pelo Interpretador}
begin
   {O cmd abstr. da linha L eh carregar o RegL com o valor corrente em P}
   {Depois dessa acao eh preciso testar se entra ou nao no bloco Do-oD}
   {Cria-se uma outra acao seguinte `a rotulada L p/ testar o registr RegL}
   { para um rotulo L pode-se criar um rotulo L*1000 + NumRTstReg, p exemplo}
   {Empilha o rotulo do DO (teste de RegL) para associar ao OD que o fecha}

{   EmpilhaRotuloDO(L,PilhaDO);}
   Empilha(L,Topo);
   {1o cmd Interpretador: carga em execucao do registrador R(L) com valor(P) }
   {O vetor REG de Registros de Controle eh usado apenas em tempo de execucao}
   with PRG^[NCAbs] do
   begin
      rotu := L;
      cond := 0; {indica que nao ha guarda: apena faca a acao indicada}
      with acao do
      begin
         cmdI := IREG; {cmd de carga em registrador de controle de loop}
         par1 := P;
         par2 := 0;
      end;
      desv := 0; {indica que basta seguir a sequencia natural dos cmds}
   end;
   new(CAbs);
   inc(NCAbs);              {cria outro comando interno do Interpretador}
   {c/ rotulo NUM_Rotulos+L, cria um cmd de teste R(L)=0?, true->GO desv}
   with PRG^[NCAbs] do
   begin
      rotu := Num_Rotulos+L; {sera usado no OD p/ retornar e testar R(L)}
      cond := L;   {indica que o registrador para teste eh o do rotulo L}
      with acao do
      begin
         cmdI := NULL; {nao ha acao interna}
         par1 := 0;
         par2 := 0;
      end;
      desv := 0; {quando achar o Od correspondente completa com rotulo da}
   end;          {instrucao seguinte ao Od}
end;
{----------------------------------------------------------------------------}
procedure GeraOd(L:integer);
{Carrega um comando OD do progr. abstrato a ser executado pelo Interpretador}
var L_DO:integer;
begin
   {if PilhaDO<>nil then}
   if Topo<>0 then
      {DesempilhaRotuloDO(L_DO,PilhaDO)} {obtem rotulo da instrucao DO}
      Desempilha(L_DO,Topo)
   else
      ErroSintatico('do/od nao fecha');
   {instrucao dec(R(L_DO)) e retorna ao label seguinte ao L_DO}
   with PRG^[NCAbs] do
   begin
      rotu := L;
      cond := 0; {indica que nao ha locacao para ser comparada com 0}
      with acao do
       20 C  0 ICOP  3  1    0
   30 C  0 IREG  2  0    0
 5030 C 30 NULL  0  0    6
   40 C  0 IINC  3  0    0
   50 C  0 IDEC 30  0 5030
                                                                                                                                                                                                                                                                                                                                                                                    ^[NCAbs] do
   begin
      rotu := L;
      cond := 0; {indica que nao ha locacao para ser comparada com 0}
      with acao do
      begin
         cmdI := NULL;
         par1 := 0;
         par2 := 0;
      end;
      desv := P; {indica que basta seguir a sequencia natural dos cmds}
   end;
end;
{----------------------------------------------------------------------------}
Procedure ResolveDesvioAberto(L:integer);
{ Preenche campo desv da 2a parte do cmd abstrato do ultimo DO aberto  }
{ O cmd que deve ser preenchido tem rotulo desempilhado pelo ultimo OD }
{ L eh o desvio para o fim do DO aberto (rotulo da instr seguinte ao OD)}
var i:integer;
begin
   i:=1;
   while (PRG^[i].rotu <> DESVIOaberto) and (i<=NCAbs) do
      inc(i);
   PRG^[i].desv := L;  {DO c/ desvio em aberto recebe rotulo seguinte ao OD}
   DESVIOaberto := 0;   {nao ha mais DO com desvio em aberto para finalizar}
end;

Function TemDesvioAberto:boolean;
begin
   TemDesvioAberto := DESVIOaberto <> 0;
end;

{----------------------------------------------------------------------------}
Procedure CarregaCmd(SCmd:TLinCmd);
{Verifica a sintaxe do comando e gera as instrucoes para o interpretador}
var L,P1,P2 : integer;
    Cmd     : TcmdS;
begin
  Parse(SCmd, L, Cmd, P1, P2);
  if Cmd <> DAT_ then
  begin
    new(CAbs);                {cria um novo comando abstrato do interpretador}
    inc(NCAbs);
    if PRG = nil then {se nao tem nenhum cmd, guarda o endereco do 1o comando}
      PRG := CAbs;
    If TemDesvioAberto then {falta definir o desvio para termino do ultimo DO}
      ResolveDesvioAberto(L); {L eh o rotulo p/ onde o ultimo DO deve desviar}
    case Cmd of                                                 {quando acaba}
      RES_: GeraReset(L, P1);
      INC_: GeraIncre(L, P1);
      COP_: GeraCopy (L, P1, P2);
      JUM_: GeraJump (L, P1);         {poderia ser variavel? O que teriamos?}
      DO_ : GeraDo   (L, P1);
      OD_ : GeraOd   (L);
    end;
  end;
end;

{----------------------------------------------------------------------------}
Procedure CarregaPrograma;
{monta a estrutura de execucao do programa abstrato SIMPLE}
var LinCmd : TLinCmd;
begin
   while not eof(SimpleFile) do
   begin
      LeLinhaComando(LinCmd);
      CarregaCmd(LinCmd);
   end;
   {caso o OD seja o ultimo comando resolve desvio em aberto}
   If TemDesvioAberto then {falta definir o desvio para termino do ultimo DO}
     ResolveDesvioAberto(NCAbs+1); {forca o desvio p/ rotulo maior que todos}
end;

{----------------------------------------------------------------------------}
function VarPertenceTS(V:Identif):boolean;
{verifica pertinencia de V a Tabela de Simbolos global TS}
var Loc : integer;
begin
   Loc:=LocacaoVarTS(V); {V ja esta instalada na TS? (Loc=0 sss V ~in TS)}
   VarPertenceTS := Loc<>0;
end;

{----------------------------------------------------------------------------}
Procedure InstalaTSVar(V:Identif);
{Instala o Id da variavel numa entrada da TS, se ja nao houver uma.}
{forma de acesso: TS^[i] := 'Id';}
var Simb : PTSimb;
begin
   if VarPertenceTS(V) then   {se V ja esta na TS temos uma dupla declaracao}
      ErroSintatico(V)
   else begin
      new(Simb);                   { aloca uma entrada na tabela de s�mbolos}
      inc(NLOCS);    {conta o numero de simbs instalados para alocar memoria}
      if (TS = nil) then                                   {se TS esta vazia}
         TS := Simb;                  {guarda o endereco da primeira locacao}
      TS^[NLOCS]:=V;        {instala o identificador nessa entrada da tabela}
   end;
end;

{----------------------------------------------------------------------------}
procedure ObtemVarDecl(L:TLinCmd; var p:byte; var V:Identif);
{Percorre linha de comando e retorna p atual e Id da var encontrada.
 Se nao encontrar Id de var, retorna string vazia.}
begin
  PulaBrancos(L,p);
  V:='';
  if not FimLinCmd(L,p) then
  begin
    if not EhLetra(L[p])                     {se primeiro char nao eh letra}
    then ErroSintatico(L);
    while ( EhLetra(L[p]) or EhDigito(L[p]) ) and not(FimLinCmd(L,p)) do
    begin
      V := V + L[p];
      inc(p);
    end;
  end;
end;

{----------------------------------------------------------------------------}
Procedure InstalaVarsDeclaradas(LC:TLinCmd);
{Analisa uma linha de comando e se eh DAT, instala os Ids das variaveis
na TabSimb.}
var Cmd:TCmdS; p:byte; V:Identif; Rot:integer;
begin
   p:=1;
   ObtemRotulo(LC,p,Rot);
   ObtemCmd(LC,p,Cmd);
   if Cmd = DAT_ then
   begin
      V:='';
      ObtemVarDecl(LC,p,V);
      while V <> '' do {achando uma var V instala na TabSimb e busca outras}
      begin
         InstalaTSVar(V); {instala identificador V}
         ObtemVarDecl(LC,p,V) {busca outra var V}
      end;
   end;
end;

{----------------------------------------------------------------------------}
Procedure TrataDeclaracaoVars;
{Percorre o codigo fonte criando uma �rea cont�gua de mem�ria para
armazenar os futuros valores das vari�veis do prog. ao mesmo tempo
que instala os identificadores em uma tabela de simbolos tal que:
  Se TS^[i].Simb = 'X' entao ValSimb('X') = Mem^[i] ou seja,
  LocacaoSimb('X') = i sss TabSimb^[i].Simb = 'X'                         }
var LinC :TLinCmd; i:integer; Loc: PMem;

begin
{1a fase : cria uma tabela de simbolos}
  while not eof(SimpleFile) do
  begin
    LeLinhaComando(LinC);
    InstalaVarsDeclaradas(LinC); {Se a linha eh DAT, inst. as vars na TS}
  end;
  close(SimpleFile);
{2a fase: aloca um bloco cont�guo de mem�ria para os simbolos da tabela}
  if TS <> nil then
  begin
    new(Loc);
    MEM:= Loc;                   {guarda o endereco da primeira locacao}
    for i := 2 to NLOCS do       {acesso indexado do tipo MEM^[i]}
      new(Loc);
  end;
end;

{----------------------------------------------------------------------------}
Procedure BuscaComandoRotulado(var C:TCmdAbstrato; var i:integer; R:integer);
{retorna o cmd abstrato e sua posicao em PRG}
{se i>=NCAbs entao nao achou o comando rotulado}
begin
   i:=1;
   while (PRG^[i].rotu <> R) and (i<=NCAbs) do
      inc(i);
   C := PRG^[i]
end;
{----------------------------------------------------------------------------}
Function Zero(R:integer):boolean; { R eh o numero do registrador de controle}
var i:integer;
begin
   i:= 1;
   while (REG[i].rot <> R) and (i<=NREGs) do {acha o reg.de controle de loop}
      inc(i);
   Zero := REG[i].vR = 0;
end;

{----------------------------------------------------------------------------}
Function BuscaRegistroContr(Rl:integer):integer;
{retorna o indice do Reg Controle Rl no vetor de Registros REG}
{se Rl ainda nao esta no vetor, retorna 0}
var i:integer;
begin
   i:= 1;
   while (REG[i].rot <> Rl) and (i<=NREGs) do
      inc(i);
   if i<= NREGs then
      BuscaRegistroContr:= i
   else
      BuscaRegistroContr:= 0;
end;

{----------------------------------------------------------------------------}
Procedure DecrRegistroContr(Rl:integer);
{Se eh para decrementar entao o registro ja esta no vetor REG}
{i nunca sera 0}
var i: integer;
begin
   i:= BuscaRegistroContr(Rl);
   dec(REG[i].vR);
end;
{----------------------------------------------------------------------------}
Procedure LoadRegistroContr(Rl:integer; V:integer);
{Para Carregar um valor em Rl precisamos ver se ele ja esta instalado em REG}
var i :integer;
begin
   i:= BuscaRegistroContr(Rl);
   if i=0 then
   begin
     inc(NREGs);
     REG[NREGs].rot := Rl; {guarda o rot que identifica o Registrador do DO}
     REG[NREGs].vR  := MEM^[V]; {inicia com o valor da variavel de controle}
   end
   else {Rl ja tem uma entrada em REGs, indexada por i. Use-a.}
   begin{nao precisa criar outra entrada incrementando NREGs  }
     REG[i].rot := Rl;
     REG[i].vR := MEM^[V];
   end;
end;

{----------------------------------------------------------------------------}
Procedure ListaMem;
var i:integer; c:char;
begin
   write('< ');
   for i:=1 to NLOCS do
      write(TS^[i], '=', MEM^[i], ' ');
   write('>');
end;

{----------------------------------------------------------------------------}
Procedure MostraCapsulaMemoria;
var i:integer; c:char;
begin
   for i:=1 to NLOCS do
      write(TS^[i], ' = ', MEM^[i], ' | ');
   writeln;
   repeat c:=readkey; until c = 'p';
end;

{----------------------------------------------------------------------------}
Procedure Executa(Rot: integer);
{Interpretador da linguagem do n�vel de m�quina usada abaixo de MH}

{Executa a partir do comando rotulado Rot}
var c         :TCmdAbstrato;
    RegContr  : integer;         {identificador do Registrador de controle}
    RotAtual,
    RotDesvio :integer;
    AcaoC     : TAcaoCAbs;
    CmdInterp : TCmdi;
    Param1,Param2,                        {parametros da acao do comando I}
    i         : integer;     {posicao do cmd a executar no vetor de cmds I}
begin
  BuscaComandoRotulado(c,i,Rot);
  while (i <= NCAbs) do {enquanto comando esta na area de comandos carregados}
  begin
    RegContr  := c.cond;
    RotDesvio := c.desv;
    AcaoC     := c.acao;
    CmdInterp := AcaoC.cmdI;
    Param1    := AcaoC.par1;
    Param2    := AcaoC.par2;
    RotAtual  := Rot;    {guarda rotulo da instrucao que esta sendo executada}
    Rot:= 0;            {reseta para definir o pr�ximo rotulo a ser executado}
    case CmdInterp of
      IRES: MEM^[Param1] := 0;
      IINC: inc(MEM^[Param1]);
      IDEC: begin
             DecrRegistroContr(Param1);   {decr o Registrador rotulado Param1}
             Rot:=RotDesvio;
            end;
      IREG: LoadRegistroContr(RotAtual, Param1);
      ICOP: MEM^[Param1] := MEM^[Param2];     {copia o conteudo de P2 para P1}
      NULL: begin {determina desvio}
              if RegContr <> 0 then              {se tem Registro de Controle}
              begin
                if Zero(RegContr) then              {e ele esta zerado, entao}
                   Rot:=RotDesvio    {termina DO, desviando para depois do OD}
                else
                   Rot:=PRG^[i+1].rotu;   {entra no corpo do bloco, se Reg<>0}
              end
              else   {se tem desvio e nao eh teste de Registrador de controle}
                if (RotDesvio<>0) then       {entao faca o JUMP incondicional}
                   Rot:=RotDesvio;
            end;
    end;{case}


    if Debug then
        MostraCapsulaMemoria;

    if Rot=0 then                {se j� nao h� um r�tulo para desvio definido}
       Rot:=PRG^[i+1].rotu;{vai para a prox. instrucao na seq. de cmds de PRG}

    BuscaComandoRotulado(c,i,Rot);
  end;{while}

  {ao fim, i aponta para fora da area do programa carregado}
  Writeln('Programa terminado com o seguinte estado final:');
  ListaMem;
  halt;
end;

{----------------------------------------------------------------------------}

Function Act(a:TCmdI):string;
begin
   case a of
   IINC : Act:='IINC';
   IDEC : Act:='IDEC';
   ICOP : Act:='ICOP';
   IRES : Act:='IRES';
   IREG : Act:='IREG';
   NULL : Act:='NULL';
   end;
end;

Procedure ListaProgramaAbstrato;
var i :integer;
begin
   assign(ProgMaqVirtual,'PRG.OBJ');
   rewrite(ProgMaqVirtual);
   for i:= 1 to NCAbs do
   begin
      with PRG^[i] do
      begin
      writeln(rotu:5,' C',cond:3,' '+Act(acao.cmdI),acao.par1:3,acao.par2:3,
            desv:5);
      writeln(ProgMaqVirtual, rotu:5,' C',cond:3,' '+Act(acao.cmdI),
                              acao.par1:3,acao.par2:3,desv:5);
      end;
   end;
   Close(ProgMaqVirtual);
end;

{----------------------------------------------------------------------------}
Procedure CarregaMemoria;
{Entrada de dados na memoria do programa SIM}
var i:integer;
begin
   for i:=1 to NLOCs do
   begin
      write(TS^[i], ' := ');
      readln(MEM^[i]);
   end;
end;

{----------------------------------------------------------------------------}
begin
  NLOCS := 0;                               { nao ha nenhuma variavel alocada}
  MEM   := nil;                             { nao ha memoria alocada p/ vars }
  TS    := nil;                             { nao ha entrada na tabela simbol}
  PRG   := nil;                             { progr. abstrato nao foi criado }
  NCAbs := 0;                               { num de cmds abstratos criados  }
  NREGs := 0;                               { nao ha registrador de controle }
  DESVIOaberto := 0;                        { nao ha DO com desv indefinido  }
  Topo    := 0;
  clrscr;
  Writeln('MH V1.r1 Ago 2007      Marcelo F.Felix');
  Writeln('Inf.Industrial CEFET-Campos/UNED Maca�');
  OpenSimpleFile;                                { abre o arquivo fonte .SIM }
  TrataDeclaracaoVars;            {trata declaracao das variaveis do programa}
  CarregaMemoria;
  if Open(SimpleFile,SimpleFileName) then      {abre para a carga do programa}
     CarregaPrograma;                    { retorna o PC do inicio do programa}
  ListaProgramaAbstrato;
  Executa(PRG^[1].rotu);{exec programa a partir do rotulo do 1o cmd carregado}
end.
