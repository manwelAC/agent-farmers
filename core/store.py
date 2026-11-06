import hashlib
import json
import sqlite3
import uuid
from datetime import datetime,timezone
from pathlib import Path

def now():return datetime.now(timezone.utc).isoformat()
def uid():return uuid.uuid4().hex
def digest(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()

class Store:
    collections=('workers','projects','plans','approvals','attempts','artifacts','connections')
    def __init__(self,root):
        self.root=Path(root).resolve();self.root.mkdir(parents=True,exist_ok=True)
        self.db=sqlite3.connect(self.root/'farmers.sqlite3');self.db.row_factory=sqlite3.Row
        version=self.db.execute('PRAGMA user_version').fetchone()[0]
        if version not in (0,1):self.db.close();raise ValueError('This data folder uses a newer database format.')
        self.db.execute('PRAGMA journal_mode=WAL');self.db.execute('PRAGMA foreign_keys=ON')
        for name in self.collections:self.db.execute(f'CREATE TABLE IF NOT EXISTS {name}(id TEXT PRIMARY KEY,data TEXT NOT NULL)')
        self.db.execute('CREATE TABLE IF NOT EXISTS events(seq INTEGER PRIMARY KEY AUTOINCREMENT,at TEXT,project_id TEXT,kind TEXT,data TEXT)');self.db.commit()
        self.db.execute('PRAGMA user_version=1')
        for attempt in self.all('attempts'):
            if attempt['status']=='running':attempt.update(status='interrupted',summary='The application stopped. Outcome unknown; work was not automatically repeated.');self.put('attempts',attempt)
        for project in self.all('projects'):
            if project['status'] in ('running','planning','reviewing','queued'):
                project.update(status='interrupted',activity='Interrupted. Review partial outputs before restarting.');self.put('projects',project)
    def all(self,table):
        if table not in self.collections:raise ValueError('Unknown collection')
        return [json.loads(r[0]) for r in self.db.execute(f'SELECT data FROM {table} ORDER BY rowid')]
    def get(self,table,identifier):return next((r for r in self.all(table) if r['id']==identifier),None)
    def put(self,table,value):
        if table not in self.collections:raise ValueError('Unknown collection')
        with self.db:self.db.execute(f'INSERT INTO {table} VALUES(?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data',(value['id'],json.dumps(value)))
        return value
    def event(self,project,kind,data):
        with self.db:cursor=self.db.execute('INSERT INTO events(at,project_id,kind,data) VALUES(?,?,?,?)',(now(),project,kind,json.dumps(data)))
        return cursor.lastrowid
    def events(self,project):return [dict(seq=r['seq'],at=r['at'],kind=r['kind'],data=json.loads(r['data'])) for r in self.db.execute('SELECT * FROM events WHERE project_id=? ORDER BY seq DESC LIMIT 100',(project,))][::-1]

def workspace(raw):
    folder=Path(raw).resolve(strict=True)
    if not folder.is_dir() or folder==Path(folder.anchor) or folder==Path.home():raise ValueError('Choose a dedicated project folder.')
    for name in ('boti-bot','agentplace'):
        protected=(Path.home()/'projects'/name).resolve()
        if folder==protected or folder in protected.parents or protected in folder.parents:raise ValueError('The previous/reference project is protected. Choose another workspace.')
    import os
    for key in ('WINDIR','ProgramFiles','ProgramFiles(x86)','ProgramData'):
        if os.environ.get(key):
            blocked=Path(os.environ[key]).resolve()
            if folder==blocked or blocked in folder.parents:raise ValueError('System folders cannot be workspaces.')
    return folder

def output_path(root,relative):
    if not relative or Path(relative).is_absolute() or ':' in relative:raise ValueError('Output paths must be relative to the workspace.')
    root=Path(root).resolve();path=(root/relative).resolve()
    if not path.is_relative_to(root) or path==root:raise ValueError('Output path leaves the workspace.')
    return path
