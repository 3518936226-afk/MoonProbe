"""Independent differential and unmodified upstream fixture verification; development only."""
import collections,hashlib,json,math,os,pathlib,random,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/'work'/'oracle-deps'))
from jsonschema import Draft202012Validator
OUT=pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'work'/'depth-verification'
OUT.mkdir(parents=True,exist_ok=False)
R=random.Random(20261123)
EXE=ROOT/'work'/'bin'/'moonprobe.exe'; ORACLE=ROOT/'work'/'oracle.exe'
SUITE=ROOT/'work'/'schema-suite'
def dump(p,x):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(x,ensure_ascii=True,separators=(',',':')),encoding='utf-8')
def scalar_data_ok(x):
    if isinstance(x,str):return not any(0xd800<=ord(c)<=0xdfff for c in x)
    if isinstance(x,(float,int)) and not isinstance(x,bool):return math.isfinite(x) and abs(x)<=9007199254740991
    if isinstance(x,list):return all(scalar_data_ok(v) for v in x)
    if isinstance(x,dict):return all(scalar_data_ok(k) and scalar_data_ok(v) for k,v in x.items())
    return True
def compatible(s):
    if not s:return True
    result=True
    for token in s.split(','):
        if token.startswith('<='):version=int(token[2:]);result=2020<=version
        elif token.startswith('='):version=int(token[1:]);result=2020==version
        else:version=int(token);result=2020>=version
        if 2020<=version:break
    return result
def subset(s,depth=1):
    if not isinstance(s,dict) or depth>8:return False
    t=s.get('type')
    if not isinstance(t,str) or t not in ['object','array','string','integer','number','boolean','null']:return False
    allowed={'type','title','description','enum'}|{'object':{'properties','required','additionalProperties'},'array':{'items','minItems','maxItems'},'string':{'minLength','maxLength'},'integer':{'minimum','maximum'},'number':{'minimum','maximum'}}.get(t,set())
    if set(s)-allowed:return False
    if any(not isinstance(s[k],str) for k in ['title','description'] if k in s):return False
    if 'enum' in s:
        a=s['enum']
        if t in ['object','array'] or not isinstance(a,list) or not 1<=len(a)<=64:return False
        plain={k:v for k,v in s.items() if k!='enum'}
        if any(not Draft202012Validator(plain).is_valid(x) or not scalar_data_ok(x) for x in a):return False
    if t=='object':
        p=s.get('properties',{})
        if not isinstance(p,dict) or any(not subset(v,depth+1) for v in p.values()):return False
        req=s.get('required',[])
        if not isinstance(req,list) or any(not isinstance(x,str) or x not in p for x in req) or len(set(req))!=len(req):return False
        if not isinstance(s.get('additionalProperties',True),bool):return False
    if t=='array' and ('items' not in s or not subset(s['items'],depth+1)):return False
    for lo,hi,cap in [('minItems','maxItems',64),('minLength','maxLength',1024)]:
        for k in [lo,hi]:
            if k in s and (isinstance(s[k],bool) or not isinstance(s[k],(float,int)) or s[k]!=int(s[k]) or not 0<=s[k]<=cap):return False
        if s.get(lo,0)>s.get(hi,cap):return False
    for k in ['minimum','maximum']:
        if k in s and (isinstance(s[k],bool) or not isinstance(s[k],(float,int)) or not scalar_data_ok(s[k])):return False
    if s.get('minimum',-9007199254740991)>s.get('maximum',9007199254740991):return False
    if t=='integer' and math.ceil(s.get('minimum',-9007199254740991))>math.floor(s.get('maximum',9007199254740991)):return False
    return True
def run_vectors(rows,label):
    all_results=[];batch=[];size=0;part=0
    def flush():
        nonlocal batch,size,part
        if not batch:return
        file=OUT/(label+'-'+str(part)+'.json');dump(file,[{'schema':x['schema'],'data':x['data']} for x in batch])
        p=subprocess.run([str(ORACLE),str(file)],capture_output=True,text=True,encoding='utf-8',timeout=60)
        (OUT/(label+'-'+str(part)+'.stdout.json')).write_text(p.stdout,encoding='utf-8')
        if p.returncode:raise AssertionError(p.stderr)
        values=json.loads(p.stdout);assert len(values)==len(batch)
        for source,value in zip(batch,values):
            if value.get('schema_error') is not None or value['valid']!=source['expected']:
                dump(OUT/'mismatch.json',{'source':source,'native':value});raise AssertionError('Independent oracle mismatch: '+label)
        all_results.extend(values);batch=[];size=0;part+=1
    for row in rows:
        length=len(json.dumps({'schema':row['schema'],'data':row['data']},ensure_ascii=True))
        if size+length>700000:flush()
        batch.append(row);size+=length
    flush();return len(all_results)
# The selected suite records retain schema, data and expected values unchanged.
official=[];excluded=[];file_hashes={}
for file in sorted((SUITE/'validation'/'tests').rglob('*.json')):
    doc=json.loads(file.read_text(encoding='utf-8'))
    for gi,group in enumerate(doc.get('tests',[])):
        if 'schema' not in group:continue
        reason=None
        if not compatible(group.get('compatibility','')):reason='different_dialect'
        elif group.get('tags') or group.get('externalSchemas'):reason='unsupported_tag_or_external_schema'
        elif not subset(group['schema']):reason='outside_declared_schema_subset'
        for ti,test in enumerate(group.get('tests',[])):
            why=reason or (None if scalar_data_ok(test['data']) else 'outside_supported_value_representation')
            locator={'file':str(file.relative_to(SUITE)).replace('\\','/'),'group':gi,'test':ti}
            if why:excluded.append({**locator,'reason':why});continue
            original={'schema':group['schema'],'data':test['data'],'expected':test['valid'],**locator}
            official.append(original);file_hashes[locator['file']]=hashlib.sha256(file.read_bytes()).hexdigest()
assert len(official)>=30, len(official)
run_vectors(official,'official')
dump(OUT/'official-selected.json',official);dump(OUT/'official-excluded.json',excluded)
# Independent schema/data generator: never calls MoonProbe's validator to derive expected values.
def schema(depth=0):
    types=['string','integer','number','boolean','null'] if depth>=2 else ['object','array','string','integer','number','boolean','null']
    t=R.choice(types);s={'type':t}
    if t=='object':
        names=R.sample(['a','b/~','title','description','描述','0'],R.randint(1,3));s['properties']={k:schema(depth+1) for k in names};s['required']=[k for k in names if R.randrange(2)];s['additionalProperties']=bool(R.randrange(2))
    elif t=='array':s.update(items=schema(depth+1),minItems=R.randint(0,1),maxItems=R.randint(2,4))
    elif t=='string':s.update(minLength=R.randint(0,2),maxLength=R.randint(3,8))
    elif t in ['integer','number']:
        lo=R.randint(-10,3);s.update(minimum=lo,maximum=lo+R.randint(1,12))
    if t in ['string','integer','boolean','null'] and R.randrange(4)==0:
        vals=[valid(s) for _ in range(3)];s['enum']=vals
    return s
def valid(s):
    if 'enum' in s:return R.choice(s['enum'])
    t=s['type']
    if t=='object':return {k:valid(v) for k,v in s.get('properties',{}).items() if k in s.get('required',[]) or R.randrange(2)}
    if t=='array':return [valid(s['items']) for _ in range(R.randint(s.get('minItems',0),s.get('maxItems',4)))]
    if t=='string':return ''.join(R.choice(['x','界','😀','\n','~','/']) for _ in range(R.randint(s.get('minLength',0),s.get('maxLength',8))))
    if t=='integer':return R.randint(math.ceil(s.get('minimum',-10)),math.floor(s.get('maximum',10)))
    if t=='number':return R.uniform(s.get('minimum',-10),s.get('maximum',10))
    if t=='boolean':return bool(R.randrange(2))
    return None
def noise(depth=0):
    values=[None,True,False,-11,0,0.5,11,'','😀','xx界',[],{}]
    if depth<2:values.extend([[noise(depth+1),noise(depth+1)],{'a':noise(depth+1),'b/~':noise(depth+1)}])
    return R.choice(values)
schemas=[schema() for _ in range(100)];rows=[]
for si,s in enumerate(schemas):
    oracle=Draft202012Validator(s)
    for i in range(100):
        data=valid(s) if i%2==0 else noise()
        rows.append({'schema':s,'data':data,'expected':oracle.is_valid(data),'schema_id':si,'sample_id':i})
assert run_vectors(rows,'differential')==10000
dump(OUT/'schemas.json',schemas)
# Test actual production generation as well as arbitrary validation.
generated=0;unique_total=0
for si,s in enumerate(schemas):
    wrapped={'type':'object','properties':{'payload':s},'required':['payload'],'additionalProperties':False}
    spec={'name':'oracle_'+str(si),'adapter_id':'echo','input_schema':wrapped}
    file=OUT/('tool-'+str(si)+'.json');dump(file,spec)
    p=subprocess.run([str(EXE),'test',str(file),'--seed','20261123','--cases','100','--out',str(OUT/('generated-'+str(si)))],capture_output=True,text=True,encoding='utf-8',timeout=60)
    (OUT/('generated-'+str(si)+'.log')).write_text(p.stdout+p.stderr,encoding='utf-8')
    if p.returncode:dump(OUT/'generation-error.json',spec);raise AssertionError('Production generation failed '+str(si)+': '+p.stderr)
    report=json.loads((OUT/('generated-'+str(si))/'report.json').read_text(encoding='utf-8'))
    seen=set();validator=Draft202012Validator(wrapped)
    for item in report['results']:
        c=item['case'];key=json.dumps(c['args'],sort_keys=True,separators=(',',':'),ensure_ascii=True)
        assert key not in seen;seen.add(key)
        assert validator.is_valid(c['args'])==(c['expected'] is None),(si,c)
    generated+=len(seen);unique_total+=len(seen)
summary={'status':'passed','seed':20261123,'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'reference':'jsonschema 4.26.0 Draft202012Validator','suite_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=SUITE,text=True).strip(),'official_selected':len(official),'official_excluded':len(excluded),'official_exclusion_reasons':dict(collections.Counter(x['reason'] for x in excluded)),'official_source_sha256':file_hashes,'differential_schemas':len(schemas),'differential_pairs':len(rows),'generated_unique_inputs':generated,'mismatches':0}
dump(OUT/'summary.json',summary)
print(json.dumps(summary,ensure_ascii=True))
