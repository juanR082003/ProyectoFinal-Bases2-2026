"""Genera el MER (notación pata de gallo) a partir del DDL, con Graphviz."""
import re, subprocess, sys

ddl = open('/home/claude/turismouq/01_ddl_turismouq.sql', encoding='utf-8').read()
tables = {}
for m in re.finditer(r'CREATE TABLE (\w+) \((.*?)\n\);', ddl, re.S):
    name, body = m.group(1).upper(), m.group(2)
    cols, pk, fk, uq = [], set(), set(), set()
    for line in body.split('\n'):
        s = line.strip()
        if not s or s.startswith('--'):
            continue
        if s.startswith('CONSTRAINT'):
            mm = re.search(r'PRIMARY KEY \(([^)]*)\)', s)
            if mm: pk |= {c.strip() for c in mm.group(1).split(',')}
            mm = re.search(r'FOREIGN KEY \(([^)]*)\)', s)
            if mm: fk |= {c.strip() for c in mm.group(1).split(',')}
            mm = re.search(r'UNIQUE \(([^)]*)\)', s)
            if mm and len(mm.group(1).split(',')) == 1: uq |= {mm.group(1).strip()}
            continue
        w = s.split()
        if w[0] in ('REFERENCES','AND','OR') or s.startswith('(') or not re.match(r'^[a-z_]+$', w[0]):
            continue
        typ = w[1].rstrip(',')
        if 'VIRTUAL' in s: typ += ' (virtual)'
        cols.append((w[0], typ, 'NOT NULL' in s or 'IDENTITY' in s))
    tables[name] = (cols, pk, fk, uq)

COLOR = {  # por área funcional
    'MUNICIPIO': '#d7e8f7', 'TIPO_ALOJAMIENTO': '#d7e8f7',
    'ALOJAMIENTO': '#d9f0dc', 'HABITACION': '#d9f0dc', 'SERVICIO': '#d9f0dc',
    'TEMPORADA': '#fbe7c6', 'CALENDARIO': '#fbe7c6', 'TARIFA': '#fbe7c6',
    'CLIENTE': '#f3d9e6', 'RESERVA': '#f3d9e6', 'RESERVA_HABITACION': '#f3d9e6',
    'RESERVA_SERVICIO': '#f3d9e6', 'PAGO': '#f3d9e6', 'RESENA': '#f3d9e6',
    'ROL': '#e4def3', 'USUARIO_SISTEMA': '#e4def3',
}
NUEVA = {'CALENDARIO', 'ROL'}

def label(t):
    cols, pk, fk, uq = tables[t]
    title = t + ('  «agregada»' if t in NUEVA else '')
    rows = [f'<TR><TD COLSPAN="3" BGCOLOR="{COLOR[t]}"><B>{title}</B></TD></TR>']
    for c, typ, nn in cols:
        k = []
        if c in pk: k.append('PK')
        if c in fk: k.append('FK')
        if c in uq: k.append('UK')
        key = ','.join(k) or ' '
        name = f'<U>{c}</U>' if c in pk else c
        if not nn: name = f'<I>{name}</I>'
        rows.append(f'<TR><TD ALIGN="LEFT"><FONT POINT-SIZE="9" COLOR="#555555">{key}</FONT></TD>'
                    f'<TD ALIGN="LEFT">{name}</TD><TD ALIGN="LEFT"><FONT POINT-SIZE="9" COLOR="#555555">{typ}</FONT></TD></TR>')
    return '<<TABLE BORDER="1" CELLBORDER="0" CELLSPACING="0" CELLPADDING="3">' + ''.join(rows) + '</TABLE>>'

# (padre, hijo, card. lado padre, card. lado hijo, verbo)
# lado padre: 'one' = 1..1, 'zone' = 0..1 ; lado hijo: 'many0' 0..N, 'many1' 1..N, 'zone' 0..1
REL = [
    ('MUNICIPIO', 'ALOJAMIENTO', 'one', 'many0', 'ubica'),
    ('TIPO_ALOJAMIENTO', 'ALOJAMIENTO', 'one', 'many0', 'clasifica'),
    ('ALOJAMIENTO', 'HABITACION', 'one', 'many1', 'ofrece'),
    ('ALOJAMIENTO', 'SERVICIO', 'one', 'many0', 'ofrece'),
    ('HABITACION', 'TARIFA', 'one', 'many1', 'tiene precio'),
    ('TEMPORADA', 'TARIFA', 'one', 'many1', 'aplica'),
    ('TEMPORADA', 'CALENDARIO', 'one', 'many1', 'agrupa días'),
    ('CLIENTE', 'RESERVA', 'one', 'many0', 'realiza'),
    ('ALOJAMIENTO', 'RESERVA', 'one', 'many0', 'recibe'),
    ('RESERVA', 'RESERVA_HABITACION', 'one', 'many1', 'incluye'),
    ('HABITACION', 'RESERVA_HABITACION', 'one', 'many0', 'se reserva en'),
    ('RESERVA', 'RESERVA_SERVICIO', 'one', 'many0', 'contrata'),
    ('SERVICIO', 'RESERVA_SERVICIO', 'one', 'many0', 'se contrata en'),
    ('RESERVA', 'PAGO', 'one', 'many0', 'se paga con'),
    ('RESERVA', 'RESENA', 'one', 'zone', 'recibe'),
    ('ROL', 'USUARIO_SISTEMA', 'one', 'many0', 'asigna'),
    ('ALOJAMIENTO', 'USUARIO_SISTEMA', 'zone', 'many0', 'emplea'),
]
ARW = {'one': 'teetee', 'zone': 'teeodot', 'many0': 'crowodot', 'many1': 'crowtee'}
TXT = {'one': '1..1', 'zone': '0..1', 'many0': '0..N', 'many1': '1..N'}

out = ['digraph MER {',
       'graph [rankdir=LR, splines=spline, nodesep=0.45, ranksep=0.9, pad=0.3, fontname="Helvetica", '
       'label="TurismoUQ · Modelo entidad-relación (notación pata de gallo) · PK subrayada, atributos opcionales en cursiva", '
       'labelloc=t, fontsize=18];',
       'node [shape=plaintext, fontname="Helvetica", fontsize=10];',
       'edge [dir=both, fontname="Helvetica", fontsize=9, color="#444444", penwidth=1.2, arrowsize=0.9];']
for t in tables:
    out.append(f'{t} [label={label(t)}];')
for p, h, cp, ch, verbo in REL:
    out.append(f'{p} -> {h} [arrowtail={ARW[cp]}, arrowhead={ARW[ch]}, '
               f'xlabel="{verbo}\\n{TXT[cp]} : {TXT[ch]}"];')
# relación lógica (no FK): las noches de una línea de reserva se leen en CALENDARIO
out.append('CALENDARIO -> RESERVA_HABITACION [style=dashed, dir=none, color="#c07000", '
           'xlabel="noches del rango\\n[checkin, checkout)", fontcolor="#c07000"];')
out.append('}')
dot = '\n'.join(out)
open('/home/claude/turismouq/docs/mer_turismouq.dot', 'w', encoding='utf-8').write(dot)
for fmt in ('png', 'svg'):
    args = ['dot', f'-T{fmt}', '-o', f'/home/claude/turismouq/docs/mer_turismouq.{fmt}',
            '/home/claude/turismouq/docs/mer_turismouq.dot']
    if fmt == 'png':
        args.insert(1, '-Gdpi=170')
    subprocess.run(args, check=True)
print('ok', len(tables), 'tablas')
