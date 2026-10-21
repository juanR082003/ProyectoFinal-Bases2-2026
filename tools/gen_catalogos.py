"""Genera los INSERT de catálogos para 02_carga_datos.sql:
temporadas 2024-2027 (con festivos de Colombia, Ley Emiliani), festivos,
alojamientos, servicios y usuarios. Semilla fija => reproducible."""
import random, datetime as dt
from collections import OrderedDict

random.seed(20262)
D = dt.date
ONE = dt.timedelta(days=1)

def easter(y):
    a=y%19;b=y//100;c=y%100;d=b//4;e=b%4;f=(b+8)//25;g=(b-f+1)//3
    h=(19*a+b-d-g+15)%30;i=c//4;k=c%4;l=(32+2*e+2*i-h-k)%7
    m=(a+11*h+22*l)//451;mo=(h+l-7*m+114)//31;da=((h+l-7*m+114)%31)+1
    return D(y,mo,da)

def next_monday(d):
    return d + dt.timedelta(days=(7 - d.weekday()) % 7)

def festivos(y):
    e = easter(y)
    fx = {D(y,1,1):"Año Nuevo", D(y,5,1):"Día del Trabajo", D(y,7,20):"Independencia",
          D(y,8,7):"Batalla de Boyacá", D(y,12,8):"Inmaculada Concepción", D(y,12,25):"Navidad",
          e-dt.timedelta(3):"Jueves Santo", e-dt.timedelta(2):"Viernes Santo"}
    mv = {D(y,1,6):"Reyes Magos", D(y,3,19):"San José", D(y,6,29):"San Pedro y San Pablo",
          D(y,8,15):"Asunción de la Virgen", D(y,10,12):"Día de la Raza", D(y,11,1):"Todos los Santos",
          D(y,11,11):"Independencia de Cartagena", e+dt.timedelta(39):"Ascensión del Señor",
          e+dt.timedelta(60):"Corpus Christi", e+dt.timedelta(68):"Sagrado Corazón"}
    out = dict(fx)
    for d, n in mv.items():
        out.setdefault(next_monday(d), n)
    return out

INI, FIN = D(2024,1,1), D(2027,1,31)
days = []
d = INI
while d <= FIN:
    days.append(d); d += ONE

label = {}   # fecha -> (categoria, nombre base, anio_ref)
def setr(a, b, cat, name):
    x = a
    while x <= b:
        if INI <= x <= FIN:
            label[x] = (cat, name)
        x += ONE

fest_all = {}
for y in range(2023, 2028):
    fest_all.update(festivos(y))

for y in range(2024, 2028):
    e = easter(y)
    reyes = next_monday(D(y,1,6))
    fin_prev_ini = D(y-1,12,15)
    setr(fin_prev_ini, reyes-ONE, "ALTA", f"Alta fin de año {y-1}-{y}")
    if y == 2027:
        setr(reyes, D(y,1,31), "BAJA", f"Baja inicio de año {y}")
        continue
    ss_ini, ss_fin = e-dt.timedelta(9), e-ONE
    setr(reyes, ss_ini-ONE, "BAJA", f"Baja inicio de año {y}")
    setr(ss_ini, ss_fin, "ALTA", f"Alta Semana Santa {y}")
    setr(e, D(y,6,13), "MEDIA", f"Media abril-junio {y}")
    setr(D(y,6,14), D(y,7,20), "ALTA", f"Alta vacaciones mitad de año {y}")
    setr(D(y,7,21), D(y,9,30), "MEDIA", f"Media agosto-septiembre {y}")
    setr(D(y,10,1), D(y,11,30), "BAJA", f"Baja octubre-noviembre {y}")
    raza = next_monday(D(y,10,12))
    setr(raza, raza+dt.timedelta(6), "MEDIA", f"Media receso escolar octubre {y}")
    setr(D(y,12,1), D(y,12,14), "MEDIA", f"Media inicio de diciembre {y}")

# Puentes festivos: noches vie-sáb-dom (festivo lunes) o jue-vie-sáb (festivo viernes)
for f, nombre in sorted(fest_all.items()):
    if nombre in ("Jueves Santo", "Viernes Santo"):
        continue
    if f.weekday() == 0:
        a, b = f-dt.timedelta(3), f-ONE
    elif f.weekday() == 4:
        a, b = f-ONE, f+ONE
    else:
        continue
    if any(label.get(x, ("ALTA",))[0] == "ALTA" for x in (a, a+ONE, b)):
        continue  # cae dentro (o junto) de otra temporada alta
    if not (INI <= a and b <= FIN):
        continue
    setr(a, b, "ALTA", f"Alta puente {nombre} {f.year}")

assert all(x in label for x in days), "hay días sin temporada"

# Agrupar días consecutivos con la misma etiqueta
segs = []
for x in days:
    cat, name = label[x]
    if segs and segs[-1][2] == name and segs[-1][1] + ONE == x:
        segs[-1][1] = x
    else:
        segs.append([x, x, name, cat])
cnt = {}
for s in segs:
    cnt[s[2]] = cnt.get(s[2], 0) + 1
seen = {}
temporadas = []
for a, b, name, cat in segs:
    n = name
    if cnt[name] > 1:
        seen[name] = seen.get(name, 0) + 1
        n = f"{name} (tramo {seen[name]})"
    temporadas.append((n, cat, a.year, a, b))

def q(s):
    return "'" + s.replace("'", "''") + "'"
def dlit(d):
    return f"DATE '{d.isoformat()}'"

out = []
out.append("-- %d temporadas (generadas a partir del calendario de festivos de Colombia)" % len(temporadas))
for n, cat, an, a, b in temporadas:
    out.append(f"INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ({q(n)}, '{cat}', {an}, {dlit(a)}, {dlit(b)});")
TEMP_SQL = "\n".join(out)

fest_rango = sorted(f for f in fest_all if INI <= f <= FIN)
FEST_SQL = "UPDATE calendario SET es_festivo = 'S' WHERE fecha IN (\n   " + ",\n   ".join(
    ", ".join(dlit(f) for f in fest_rango[i:i+6]) for i in range(0, len(fest_rango), 6)) + ");"

# ---------------------------------------------------------------- alojamientos
# tipo: 1 finca, 2 hotel, 3 glamping, 4 hostal, 5 ecohotel
MUN = OrderedDict([(1,"Armenia"),(2,"Buenavista"),(3,"Calarcá"),(4,"Circasia"),(5,"Córdoba"),
       (6,"Filandia"),(7,"Génova"),(8,"La Tebaida"),(9,"Montenegro"),(10,"Pijao"),(11,"Quimbaya"),(12,"Salento")])
A = [
 # Armenia (12)
 (1,2,"Hotel Mirador del Parque Sucre",4),(1,2,"Hotel Torre Cafetera",5),(1,2,"Hotel Avenida Bolívar",3),
 (1,2,"Hotel Ejecutivo La Castellana",4),(1,2,"Hotel Plaza Quimbaya Centro",3),(1,2,"Gran Hotel Guadua Real",5),
 (1,2,"Hotel Los Fundadores Suites",4),(1,4,"Hostal La Calle Catorce",2),(1,4,"Hostal Ruta del Café Armenia",2),
 (1,4,"Hostal Barrio Laureles",1),(1,1,"Finca Cafetera El Edén Urbano",3),(1,5,"Ecohotel Bosque de Yarumos",4),
 # Salento (10)
 (12,4,"Hostal Calle Real de Salento",2),(12,4,"Hostal Mochileros del Cocora",1),(12,4,"Hostal Balcones de Colores",2),
 (12,3,"Glamping Domos del Valle de Cocora",4),(12,3,"Glamping Palma de Cera",5),(12,1,"Finca Cafetera La Aldea del Alto",3),
 (12,1,"Finca El Recreo de Boquía",4),(12,2,"Hotel Mirador Alto de la Cruz",4),(12,2,"Hotel Colonial Plaza Bolívar",3),
 (12,5,"Ecohotel Reserva Río Quindío",4),
 # Filandia (7)
 (6,3,"Glamping Colina Iluminada",5),(6,3,"Glamping Bosque de Bambú",4),(6,1,"Finca Cafetera Los Cerezos",4),
 (6,1,"Finca La Herencia Filandeña",3),(6,4,"Hostal El Mirador Filandia",2),(6,4,"Hostal Bahareque",2),
 (6,2,"Hotel Casona del Parque Filandia",3),
 # Montenegro (7)
 (9,1,"Finca Hotel Puerto Espejo",4),(9,1,"Finca Cafetera Villa Laura",3),(9,1,"Finca El Ocaso Cafetero",3),
 (9,1,"Finca Bambusa",4),(9,2,"Hotel Entrada al Parque",4),(9,2,"Hotel Pueblo Tapao Plaza",3),
 (9,3,"Glamping Mirador de Pisamal",4),
 # Quimbaya (6)
 (11,1,"Finca Cafetera Las Acacias",3),(11,1,"Finca Los Guaduales de Panaca",4),(11,1,"Finca La Montaña Luminosa",3),
 (11,2,"Hotel Alumbrado de Velas",4),(11,2,"Hotel Campestre El Arriero",3),(11,3,"Glamping Estrellas de Quimbaya",4),
 # Calarcá (6)
 (3,2,"Hotel Jardín Botánico",4),(3,1,"Finca Cafetera La Rochela",3),(3,1,"Finca El Mariposario",4),
 (3,4,"Hostal Alto del Río",2),(3,5,"Ecohotel Cañón del Quindío",4),(3,1,"Finca Santa Ana de Calarcá",3),
 # Circasia (4)
 (4,1,"Finca Cafetera La Pradera de Circasia",3),(4,1,"Finca La Cabaña de Barcelona",3),(4,4,"Hostal Mirador de Circasia",2),
 (4,3,"Glamping Alto de la Cruz Circasia",4),
 # La Tebaida (4)
 (8,2,"Hotel Aeropuerto El Edén",3),(8,1,"Finca Cafetera Mangos Viejos",3),(8,1,"Finca Los Samanes",4),
 (8,4,"Hostal Estación Tebaida",1),
 # Buenavista, Pijao, Génova, Córdoba (1 c/u)
 (2,1,"Finca Mirador del Valle Buenavista",4),(10,1,"Finca Cafetera Pueblo Sin Prisa",3),
 (7,1,"Finca El Páramo de Génova",3),(5,4,"Hostal Quebrada Córdoba",2),
]
assert len(A) == 60 and len({a[2] for a in A}) == 60

CALLES = ["Cra 14 # %d-%02d","Calle %d # %d-%02d","Av. Bolívar # %d-%02d","Cra %d # %d-%02d"]
def slug(s):
    import unicodedata
    s = unicodedata.normalize("NFKD", s).encode("ascii","ignore").decode().lower()
    return "".join(ch for ch in s if ch.isalnum())[:28]

aloj_sql = []
for idx, (m, t, nombre, est) in enumerate(A, 1):
    mun = MUN[m]
    if t == 2 or (t == 4 and m in (1,12,6,3)):
        if m == 1:
            dirc = "Cra %d # %d-%02d, Armenia" % (random.randint(10,19), random.randint(10,50), random.randint(1,99))
        else:
            dirc = "Calle %d # %d-%02d, %s" % (random.randint(2,9), random.randint(2,12), random.randint(1,60), mun)
    else:
        ver = random.choice(["La Palmera","El Caimo","Boquía","Palestina","La Bella","Pantanillo","El Roble",
                             "La Esperanza","Llanitos","San Juan","El Agrado","La Granja","Barcelona Alta"])
        dirc = "Vereda %s, km %d vía %s" % (ver, random.randint(1,12), mun)
    nit = "9%08d-%d" % (random.randint(10000000, 99999999), random.randint(0,9))
    tel = "606 7%02d %04d" % (random.randint(30,59), random.randint(0,9999)) if random.random()<0.6 else \
          "31%d %03d %04d" % (random.randint(0,9), random.randint(0,999), random.randint(0,9999))
    sl = slug(nombre)
    correo = f"reservas@{sl}.com.co"
    web = f"https://www.{sl}.com.co" if random.random() < 0.7 else None
    freg = D(2023, 1, 1) + dt.timedelta(days=random.randint(0, 270))
    aloj_sql.append(
        "INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) "
        f"VALUES ({m}, {t}, {q(nombre)}, '{nit}', {q(dirc)}, {est}, '{tel}', '{correo}', "
        f"{q(web) if web else 'NULL'}, {dlit(freg)});")
ALOJ_SQL = "\n".join(aloj_sql)

# ---------------------------------------------------------------- servicios
CAT = {
 "Desayuno típico": ("Calentado paisa o desayuno continental con café de origen", 18000, 32000, "POR_PERSONA"),
 "Tour del café": ("Recorrido por el cafetal, beneficio y catación guiada", 45000, 90000, "POR_PERSONA"),
 "Transporte aeropuerto El Edén": ("Traslado privado desde o hacia el aeropuerto El Edén", 60000, 140000, "POR_SERVICIO"),
 "Alquiler de bicicletas": ("Bicicleta de montaña con casco por día", 35000, 60000, "POR_DIA"),
 "Spa y masajes": ("Masaje relajante de 60 minutos con aceites de café", 90000, 160000, "POR_PERSONA"),
 "Cabalgata": ("Cabalgata guiada de 2 horas por senderos rurales", 50000, 85000, "POR_PERSONA"),
 "Tour Valle de Cocora": ("Excursión guiada al Valle de Cocora y palmas de cera", 70000, 120000, "POR_PERSONA"),
 "Cena romántica": ("Cena para dos con decoración especial", 120000, 220000, "POR_SERVICIO"),
 "Avistamiento de aves": ("Salida de madrugada con guía ornitólogo", 60000, 110000, "POR_PERSONA"),
 "Lavandería": ("Lavado y planchado por bolsa", 20000, 35000, "POR_SERVICIO"),
 "Parqueadero": ("Parqueadero cubierto por noche", 10000, 20000, "POR_DIA"),
 "Entradas Parque del Café": ("Pasaporte de ingreso al Parque Nacional del Café", 75000, 110000, "POR_PERSONA"),
 "Entradas PANACA": ("Ingreso a PANACA con transporte", 80000, 120000, "POR_PERSONA"),
 "Jacuzzi privado": ("Jacuzzi al aire libre por 2 horas", 60000, 120000, "POR_SERVICIO"),
 "Fogata y asado": ("Kit de fogata con asado para el grupo", 70000, 150000, "POR_SERVICIO"),
 "Clase de barismo": ("Taller de métodos de preparación de café", 50000, 80000, "POR_PERSONA"),
}
POR_TIPO = {
 1: ["Desayuno típico","Tour del café","Cabalgata","Transporte aeropuerto El Edén","Fogata y asado","Avistamiento de aves","Clase de barismo","Entradas Parque del Café"],
 2: ["Desayuno típico","Transporte aeropuerto El Edén","Spa y masajes","Lavandería","Parqueadero","Entradas Parque del Café","Entradas PANACA","Tour del café"],
 3: ["Desayuno típico","Jacuzzi privado","Cena romántica","Fogata y asado","Avistamiento de aves","Transporte aeropuerto El Edén"],
 4: ["Desayuno típico","Alquiler de bicicletas","Tour Valle de Cocora","Lavandería","Tour del café"],
 5: ["Desayuno típico","Avistamiento de aves","Spa y masajes","Tour del café","Cabalgata","Transporte aeropuerto El Edén"],
}
srv_sql = []
nsrv = 0
for (m, t, nombre, est) in A:
    lst = POR_TIPO[t][:]
    if m == 12 and "Tour Valle de Cocora" not in lst:
        lst.append("Tour Valle de Cocora")
    k = random.randint(3, min(6, len(lst)))
    elegidos = ["Desayuno típico"] + random.sample([s for s in lst if s != "Desayuno típico"], k-1)
    for s in elegidos:
        desc, lo, hi, uni = CAT[s]
        precio = round(random.uniform(lo, hi) * (0.85 + 0.06*est) / 1000) * 1000
        srv_sql.append(
            "INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ("
            f"(SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = {q(nombre)}), {q(s)}, {q(desc)}, {precio}, '{uni}');")
        nsrv += 1
SRV_SQL = f"-- {nsrv} servicios repartidos entre los 60 alojamientos\n" + "\n".join(srv_sql)

# ---------------------------------------------------------------- usuarios
TIPO_N = {1:"Finca cafetera",2:"Hotel",3:"Glamping",4:"Hostal",5:"Ecohotel"}
enc = {}
for (m, t, nombre, est) in A:
    enc.setdefault(t, nombre)
U = [
 ("admin.plataforma", "Laura Marcela Ospina Gil", 1, "PLATAFORMA", None),
 ("admin.soporte", "Andrés Felipe Cardona Ruiz", 1, "PLATAFORMA", None),
 ("gerente.general", "Patricia Elena Henao Arango", 2, "PLATAFORMA", None),
 ("auditor.interno", "Jorge Iván Valencia Mejía", 3, "PLATAFORMA", None),
 ("enc.finca", "Carlos Mario Londoño Castaño", 4, "ALOJAMIENTO", enc[1]),
 ("enc.hotel", "Diana Carolina Restrepo Giraldo", 4, "ALOJAMIENTO", enc[2]),
 ("enc.glamping", "Santiago Arias Montoya", 4, "ALOJAMIENTO", enc[3]),
 ("enc.hostal", "Valentina Quintero López", 4, "ALOJAMIENTO", enc[4]),
 ("enc.ecohotel", "Julián David Ramírez Toro", 4, "ALOJAMIENTO", enc[5]),
 ("recep.hotel1", "María José Salazar Bedoya", 5, "ALOJAMIENTO", enc[2]),
 ("recep.hotel2", "Juan Sebastián Correa Duque", 5, "ALOJAMIENTO", "Hotel Torre Cafetera"),
 ("recep.salento", "Natalia Gómez Rincón", 5, "ALOJAMIENTO", "Hostal Calle Real de Salento"),
]
us_sql = []
for u, n, r, amb, al in U:
    alv = f"(SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = {q(al)})" if al else "NULL"
    us_sql.append("INSERT INTO usuario_sistema (username, nombre_completo, correo, id_rol, ambito_rol, id_alojamiento) "
                  f"VALUES ('{u}', {q(n)}, '{u}@turismouq.com.co', {r}, '{amb}', {alv});")
US_SQL = "\n".join(us_sql)

if __name__ == "__main__":
    import sys, json
    parts = {"TEMP": TEMP_SQL, "FEST": FEST_SQL, "ALOJ": ALOJ_SQL, "SRV": SRV_SQL, "US": US_SQL}
    tpl = open(sys.argv[1], encoding="utf-8").read()
    for k, v in parts.items():
        tpl = tpl.replace("@@" + k + "@@", v)
    assert "@@" not in tpl
    open(sys.argv[2], "w", encoding="utf-8").write(tpl)
    print("temporadas:", len(temporadas), "festivos:", len(fest_rango), "servicios:", nsrv)
    for t in temporadas[:40]:
        print(t[1], t[3], t[4], t[0])
