"""Explicit no-tools session verification; uses provider account usage."""
import asyncio
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from core import providers

async def main():
    spec=(await providers.discover())['antigravity']
    await providers.verify(spec,Path.cwd())
    print('Live Antigravity session verification passed')
if __name__=='__main__':asyncio.run(main())
