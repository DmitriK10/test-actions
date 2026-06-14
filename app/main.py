"""
Простое FastAPI приложение для демонстрации CI/CD.
Эндпоинты: /time, /date, /datetime, /convert
"""
from fastapi import FastAPI, HTTPException
from datetime import datetime
import pytz
from typing import Optional

app = FastAPI(title="Time Server API", description="Возвращает время и дату", version="1.0")

@app.get("/")
def root():
    return {"message": "Добро пожаловать в Time Server API"}

@app.get("/time")
def get_time():
    """Текущее UTC время"""
    return {"utc_time": datetime.utcnow().isoformat() + "Z"}

@app.get("/date")
def get_date():
    """Текущая дата (UTC)"""
    return {"utc_date": datetime.utcnow().date().isoformat()}

@app.get("/datetime")
def get_datetime():
    """Полная дата+время UTC"""
    return {"utc_datetime": datetime.utcnow().isoformat() + "Z"}

@app.get("/convert")
def convert_time(time_str: str, from_tz: str, to_tz: str):
    """
    Конвертация времени между часовыми поясами.
    time_str: ISO формат (например, 2025-03-30T12:00:00)
    from_tz/to_tz: название часового пояса (например, Europe/Moscow, America/New_York)
    """
    try:
        dt = datetime.fromisoformat(time_str)
        from_zone = pytz.timezone(from_tz)
        to_zone = pytz.timezone(to_tz)
        dt_from = from_zone.localize(dt)
        dt_to = dt_from.astimezone(to_zone)
        return {"original": dt_from.isoformat(), "converted": dt_to.isoformat()}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))