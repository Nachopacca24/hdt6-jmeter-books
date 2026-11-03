# Resultados

Cada nivel corrió sin interfaz gráfica con ramp-up de 10 s y 60 s sostenidos, y el API se reseteó antes de cada corrida:

```powershell
uv run api.py                 # en otra terminal
.\correr.ps1                  # corre los cinco niveles
```

Cada corrida se hizo con `jmeter -n -t plan.jmx -Jusers=<n> -Jrampup=10 -Jhold=60 -l ... -e -o ...`. La puerta se corrió con `python gate.py <carpeta del reporte>`. Los números salen del valor `Total` de `resultados/<usuarios>/statistics.json`, y los tiempos están en ms.

| Usuarios | Muestras | Solicitudes por segundo | p50 | p95 | p99 | Errores | Código de salida de la puerta |
|---|---|---|---|---|---|---|---|
| 10 | 38 922 | 560.2 | 23 | 39 | 47 | 0.00 % | 0 |
| 50 | 39 025 | 552.3 | 121 | 171 | 206 | 0.00 % | 1 |
| 100 | 39 141 | 551.9 | 236 | 357 | 431 | 0.00 % | 1 |
| 200 | 38 794 | 543.9 | 444 | 649 | 1 014 | 0.00 % | 1 |
| 500 | 251 709 | 3 512.1 | 18 | 37 | 1 547 | 87.82 % | 1 |

**En qué nivel el p95 pasó de 100 ms por primera vez.** Fue con **50 usuarios**, con un p95 de 171 ms. Con 10 usuarios el p95 era de 39 ms. Desde ahí casi se duplica cada vez que se duplican los usuarios (357 ms con 100 y 649 ms con 200), porque las solicitudes por segundo no suben: cada usuario de más solo se suma a la cola.

**Qué pasó con las solicitudes por segundo entre 200 y 500 usuarios.** El total pasó de 543.9/s a 3 512.1/s, pero ese aumento es engañoso. El 87.82 % de las muestras de 500 usuarios son errores `HttpHostConnectException` (*Connect to 127.0.0.1:8000 failed*): el API ya no aceptaba más conexiones y JMeter las veía fallar casi al instante. Por eso el p50 baja a 18 ms y el p95 a 37 ms, y por eso la puerta no falla por el p95 sino por los errores. Las solicitudes que sí tuvieron éxito fueron 30 659 en unos 71.7 s, es decir **~428/s**. Eso es menos que las 543.9/s de 200 usuarios: con más carga, el trabajo útil bajó un ~21 %.

**CPU durante la corrida de 500 usuarios.** La máquina tiene **24 núcleos lógicos**. El CPU se mide en porcentaje de un núcleo (100 % = un núcleo entero), con una muestra por segundo durante la parte sostenida (`corridas/500/cpu.json`):

| Proceso | Promedio | Máximo |
|---|---|---|
| API (uvicorn, un proceso de Python) | 73.6 % | 101 % |
| JMeter (java) | 446.1 % | 1 241.5 % |

El límite lo puso **el API**. Es un solo proceso de Python con un solo event loop, así que no puede usar más de un núcleo, y ya estaba en ~99 % de un núcleo desde la corrida de 10 usuarios. Por eso las solicitudes por segundo se quedan planas en ~550/s entre 10 y 200 usuarios, aunque la máquina tiene 24 núcleos. Con 500 usuarios la cola de conexiones del API se llenó y empezó a rechazar conexiones. JMeter usó en promedio unos 4.5 núcleos y como máximo ~12.4, sobre todo reintentando esas conexiones rechazadas, y siempre le sobraron más de 10 núcleos. No fue el cuello de botella.
