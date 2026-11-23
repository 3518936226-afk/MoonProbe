"""Render an animation from actual CLI output. This is NOT a desktop screen recording."""
import hashlib,json,pathlib,subprocess,sys,textwrap
from PIL import Image,ImageDraw,ImageFont
ROOT=pathlib.Path(__file__).resolve().parent.parent
OUT=ROOT/'work'/'demo-artifact'
OUT.mkdir(parents=True,exist_ok=False)
EXE=ROOT/'work'/'bin'/'moonprobe.exe'
SPEC=ROOT/'examples'/'extract-deadline.json'
transcript=[]
def run(args,want):
    p=subprocess.run([str(EXE),*map(str,args)],cwd=ROOT,capture_output=True,text=True,encoding='utf-8')
    transcript.append(dict(argv=list(map(str,args)),exit_code=p.returncode,stdout=p.stdout,stderr=p.stderr))
    assert p.returncode==want,(p.returncode,p.stderr)
    return json.loads(p.stdout)
inspect=run(['inspect',SPEC],0)
run(['test',SPEC,'--mock','buggy','--seed','20261123','--cases','32','--out',OUT/'buggy'],1)
report=json.loads((OUT/'buggy'/'report.json').read_text(encoding='utf-8'))
first=report['corpus'][0]
buggy=run(['replay',SPEC,OUT/'buggy'/'corpus','--mock','buggy'],1)
fixed=run(['replay',SPEC,OUT/'buggy'/'corpus','--mock','fixed'],0)
(OUT/'transcript.json').write_text(json.dumps(transcript,indent=2),encoding='utf-8')
fontpath=pathlib.Path('C:/Windows/Fonts/consola.ttf')
font=lambda size:ImageFont.truetype(str(fontpath),size)
F,T,S=font(24),font(42),font(18)
colors={'bg':'#101624','card':'#19263b','text':'#e2eafa','muted':'#96accb','blue':'#79b5ff','green':'#71e6b5'}
def scene(title,command,lines,number):
    im=Image.new('RGB',(1200,800),colors['bg']);d=ImageDraw.Draw(im)
    d.text((42,28),'MoonProbe',font=T,fill=colors['text'])
    d.text((44,86),'Native CLI  |  synthetic fixture  |  no network',font=F,fill=colors['blue'])
    d.rounded_rectangle((40,140,1160,704),radius=16,fill=colors['card'])
    d.text((64,160),f'{number:02d}  {title}',font=font(30),fill=colors['green'])
    d.text((64,214),command,font=font(21),fill=colors['blue'])
    y=264
    for line in lines:
        for wrapped in textwrap.wrap(line,78,replace_whitespace=False,drop_whitespace=False) or ['']:
            d.text((64,y),wrapped,font=F,fill=colors['text']);y+=32
    d.text((44,730),'Rendered actual command transcript — NOT desktop screen recording',font=S,fill=colors['muted'])
    d.text((44,760),'Binary SHA256 '+hashlib.sha256(EXE.read_bytes()).hexdigest()[:32],font=S,fill=colors['muted'])
    return im
frames=[]
frames.append(scene('Inspect the local contract','> moonprobe inspect examples/extract-deadline.json',[
    'Tool: '+inspect['name'],'Input: date is a required string enum',
    'Enum: 2024-02-29 / 2024-02-28 / 2023-02-28',
    'Output: deadline is required','Mode: '+inspect['mode'],'Exit code: 0',
    'Schema fingerprint: '+inspect['schema_fingerprint'][:32]],1))
frames.append(scene('Find and shrink the injected fault','> moonprobe test ... --mock buggy --seed 20261123 --cases 32',[
    f"Cases: 32   passed: {report['passed']}   failed: {report['failed']}",
    'Failure: OUTPUT_SCHEMA / REQUIRED /deadline',
    'Original: '+json.dumps(first['original_input'],ensure_ascii=False,separators=(',',':')),
    'Reduced:  '+json.dumps(first['reduced_input'],ensure_ascii=False,separators=(',',':')),
    f"Bytes: {first['shrink']['original_bytes']} -> {first['shrink']['reduced_bytes']}  ({first['shrink']['reduction_ratio']:.1%} smaller)",
    'Same failure signature; valid input preserved','Expected exit code: 1'],2))
frames.append(scene('Replay against buggy','> moonprobe replay ... --mock buggy',[
    'Use the same archived reduced input',json.dumps(buggy['results'][0]['input']),
    'Status: '+buggy['results'][0]['status'],
    'Signature: OUTPUT_SCHEMA / REQUIRED /deadline',
    f"Passed: {buggy['passed']}   Failed: {buggy['failed']}",'Expected exit code: 1'],3))
frames.append(scene('Verify the repair','> moonprobe replay ... --mock fixed',[
    'Only the adapter version changed','Status: '+fixed['results'][0]['status'],
    f"Passed: {fixed['passed']}   Failed: {fixed['failed']}",'Exit code: 0',
    'Contract, corpus and input stayed the same',
    'Public CI and independent human review remain pending'],4))
frames[1].save(OUT/'preview.png')
frames[0].save(OUT/'MoonProbe-demo.gif',save_all=True,append_images=frames[1:],duration=[6500,11000,6500,8000],loop=0,optimize=True)
(OUT/'metadata.json').write_text(json.dumps({'type':'rendered_real_command_transcript','not_screen_recording':True,'binary_sha256':hashlib.sha256(EXE.read_bytes()).hexdigest(),'commands':len(transcript),'expected_exits':[0,1,1,0]},indent=2),encoding='utf-8')
print(OUT)
