import os
from flask import Flask, render_template, request, redirect, url_for, flash
import oracledb

app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY", "sicac-dev-secret-change-in-prod")

DB_USER = os.getenv("SICAC_APP_USER", "SICAC")
DB_PASSWORD = os.getenv("SICAC_APP_PWD") or os.getenv("SICAC_OWNER_PWD", "")
DB_DSN = os.getenv("SICAC_DB_DSN", "127.0.0.1:1521/FREEPDB1")


def get_conn():
    if not DB_PASSWORD:
        raise RuntimeError("Falta configurar SICAC_APP_PWD o SICAC_OWNER_PWD en el entorno.")
    return oracledb.connect(user=DB_USER, password=DB_PASSWORD, dsn=DB_DSN)


def rows_to_dicts(cursor):
    cols = [d[0].lower() for d in cursor.description]
    return [dict(zip(cols, row)) for row in cursor.fetchall()]


@app.route("/")
def index():
    kpis = {
        "total_cargas": 0,
        "total_litros": 0.0,
        "monto_cobrado": 0.0,
        "monto_subvencionado": 0.0,
        "alertas_pendientes": 0,
        "alertas_criticas": 0,
    }
    subvenciones = []
    alertas = []
    inventario = []
    personas_mask = []
    error_msg = None

    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT NVL(SUM(total_cargas_validas), 0),
                           NVL(SUM(total_litros_despachados), 0),
                           NVL(SUM(monto_cobrado_bs), 0),
                           NVL(SUM(monto_subvencionado_bs), 0)
                      FROM vw_resumen_subvencion_estacion
                """)
                r_kpi = cur.fetchone()
                if r_kpi:
                    kpis["total_cargas"] = int(r_kpi[0] or 0)
                    kpis["total_litros"] = float(r_kpi[1] or 0)
                    kpis["monto_cobrado"] = float(r_kpi[2] or 0)
                    kpis["monto_subvencionado"] = float(r_kpi[3] or 0)

                cur.execute("""
                    SELECT COUNT(*),
                           SUM(CASE WHEN nivel_riesgo = 'CRITICO' THEN 1 ELSE 0 END)
                      FROM vw_alertas_detalle
                     WHERE estado_alerta = 'PENDIENTE'
                """)
                r_al = cur.fetchone()
                if r_al:
                    kpis["alertas_pendientes"] = int(r_al[0] or 0)
                    kpis["alertas_criticas"] = int(r_al[1] or 0)

                cur.execute("""
                    SELECT estacion, combustible, total_cargas_validas,
                           total_litros_despachados, monto_cobrado_bs, monto_subvencionado_bs
                      FROM vw_resumen_subvencion_estacion
                     ORDER BY monto_subvencionado_bs DESC
                     FETCH FIRST 10 ROWS ONLY
                """)
                subvenciones = rows_to_dicts(cur)

                cur.execute("""
                    SELECT id_alerta, nivel_riesgo, codigo_regla, regla, placa,
                           tipo_vehiculo, conductor, estacion, cantidad_litros,
                           valor_detectado, valor_umbral, estado_alerta
                      FROM vw_alertas_detalle
                     ORDER BY CASE estado_alerta WHEN 'PENDIENTE' THEN 0 ELSE 1 END,
                              id_alerta DESC
                     FETCH FIRST 15 ROWS ONLY
                """)
                alertas = rows_to_dicts(cur)

                cur.execute("""
                    SELECT estacion, combustible, litros_ingresados,
                           litros_despachados, saldo_teorico_litros
                      FROM vw_balance_inventario_estacion
                     ORDER BY saldo_teorico_litros ASC
                     FETCH FIRST 10 ROWS ONLY
                """)
                inventario = rows_to_dicts(cur)

                cur.execute("""
                    SELECT id_persona, ci_enmascarado, expedido, nombres,
                           apellido_paterno, inicial_materno, telefono_enmascarado, estado
                      FROM vw_persona_enmascarada
                     ORDER BY id_persona
                     FETCH FIRST 8 ROWS ONLY
                """)
                personas_mask = rows_to_dicts(cur)

    except Exception as exc:
        error_msg = str(exc)

    return render_template(
        "index.html",
        kpis=kpis,
        subvenciones=subvenciones,
        alertas=alertas,
        inventario=inventario,
        personas_mask=personas_mask,
        error_msg=error_msg,
        db_user=DB_USER,
        db_dsn=DB_DSN,
    )


@app.route("/alerta/<int:id_alerta>/atender", methods=["POST"])
def atender_alerta(id_alerta):
    nuevo_estado = request.form.get("estado", "ATENDIDA")
    observacion = request.form.get("observacion", "Revisada desde dashboard SICAC")
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id_funcionario FROM funcionario WHERE ROWNUM = 1")
                row_fun = cur.fetchone()
                id_revisor = row_fun[0] if row_fun else None
                cur.callproc("sp_gestionar_alerta", [id_alerta, nuevo_estado, id_revisor, observacion])
            conn.commit()
        flash(f"Alerta #{id_alerta} actualizada a {nuevo_estado}.", "ok")
    except Exception as exc:
        flash(f"Error al actualizar alerta #{id_alerta}: {exc}", "err")
    return redirect(url_for("index"))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
