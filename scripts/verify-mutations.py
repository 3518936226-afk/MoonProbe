"""Twelve predetermined semantic mutations in disposable D-drive copies, never production flags."""
import hashlib,json,os,pathlib,re,shutil,subprocess,sys,time
ROOT=pathlib.Path(__file__).resolve().parent.parent
OUT=pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'work'/'mutation-verification'
OUT.mkdir(parents=True,exist_ok=False)
RULES=[
 ('M01_required','engine/ir.mbt','if !m.contains(k)','if false'),
 ('M02_extra_properties','engine/ir.mbt','else if !extra','else if false'),
 ('M03_fractional_integer','engine/ir.mbt',' && n.floor() == n',''),
 ('M04_minimum_endpoint','engine/ir.mbt','x < n','x <= n'),
 ('M05_maximum_endpoint','engine/ir.mbt','x > n','x >= n'),
 ('M06_utf16_length','engine/ir.mbt','x.char_length()','x.length()'),
 ('M07_enum_ignored','engine/ir.mbt','!a.contains(v)','false'),
 ('M08_array_items','engine/ir.mbt','validate_ir(sub, x, path=ptr(path, i.to_string()))','None'),
 ('M09_nested_property','engine/ir.mbt','validate_ir(sub, m[k], path=ptr(path, k))','None'),
 ('M10_output_unchecked','engine/adapters.mbt','if spec.output_ir is Some(schema)','if false && spec.output_ir is Some(schema)'),
 ('M11_changed_signature','engine/shrink.mbt','outcome.failure == Some(signature)','outcome.failure is Some(_)'),
 ('M12_fingerprint','engine/report.mbt','text(field(e, "schema_fingerprint")) != spec.fingerprint','false'),
]
summary=[]
env=os.environ.copy();env['MOON_HOME']=str(ROOT/'toolchain');env['TEMP']=str(ROOT/'work'/'tmp');env['TMP']=env['TEMP']
for identifier,file,old,new in RULES:
    scratch=OUT/identifier;scratch.mkdir()
    for folder in ['engine','cmd','scripts']:shutil.copytree(ROOT/folder,scratch/folder)
    shutil.copy2(ROOT/'moon.mod',scratch/'moon.mod')
    source=(scratch/file).read_text(encoding='utf-8');matches=source.count(old)
    if matches!=1:raise AssertionError((identifier,'mutation must match exactly once',matches))
    mutated=source.replace(old,new,1);(scratch/file).write_text(mutated,encoding='utf-8')
    build=subprocess.run(['pwsh','-NoProfile','-File',str(scratch/'scripts'/'build-native.ps1'),'-Test'],cwd=scratch,env=env,capture_output=True,text=True,encoding='utf-8',timeout=180)
    (scratch/'build.log').write_text(build.stdout+build.stderr,encoding='utf-8')
    if build.returncode:raise AssertionError(identifier+' invalid mutant: compilation failed')
    metadata=json.loads((scratch/'_build/native/release/test/engine/__whitebox_test_info.json').read_text(encoding='utf-8'))
    selector='/'.join(name+':0-'+str(len(tests)) for name,tests in metadata['tests'].items())
    expected=sum(len(x) for x in metadata['tests'].values())
    test=subprocess.run([str(scratch/'work/engine-tests.exe'),selector],cwd=scratch,env=env,capture_output=True,text=True,encoding='utf-8',timeout=60)
    (scratch/'tests.log').write_text(test.stdout+test.stderr,encoding='utf-8')
    records=[json.loads(line) for line in test.stdout.splitlines() if line.startswith('{')]
    results=[r for r in records if r.get('type')=='result'];failures=[r for r in results if r.get('message')]
    if len(results)!=expected:raise AssertionError(identifier+' incomplete test driver results')
    row={'id':identifier,'file':file,'source_sha256':hashlib.sha256(source.encode()).hexdigest(),'mutated_sha256':hashlib.sha256(mutated.encode()).hexdigest(),'old':old,'new':new,'compiled':True,'status':'killed' if failures else 'survived','failed_tests':[{'file':r['file'],'index':r['index'],'message':r['message']} for r in failures]}
    summary.append(row);(OUT/'progress.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print(identifier+': '+row['status']+' ('+str(len(failures))+' failing tests)',flush=True)
    if not failures:raise AssertionError(identifier+' survived')
report={'status':'passed','source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'defined':12,'compiled':len(summary),'killed':sum(x['status']=='killed' for x in summary),'survived':sum(x['status']=='survived' for x in summary),'mutations':summary}
(OUT/'summary.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('All 12 non-equivalent compiled mutations killed.',flush=True)
