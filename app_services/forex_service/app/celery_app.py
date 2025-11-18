from celery import Celery
from celery.schedules import crontab
import os
import sys

# Add common module to path
common_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'common'))
if os.path.exists(common_path):
    sys.path.insert(0, common_path)
else:
    sys.path.insert(0, '/app/common')

from config import config

celery_app = Celery(
    'fx',
    broker=config.REDIS_BROKER_URL,
    backend=config.REDIS_RESULT_BACKEND,
)

celery_app.conf.update(
    task_serializer='json',
    accept_content=['json'],
    result_serializer='json',
    task_acks_late=True,
    worker_prefetch_multiplier=1,
    task_time_limit=60,
    task_soft_time_limit=45,
)

# Every 5 hours on the hour
celery_app.conf.beat_schedule = {
    'refresh-fx-every-5-hours': {
        'task': 'tasks.refresh_fx_rates',
        'schedule': crontab(minute=0, hour='*/5'),
    }
}

# Import tasks to register them (must be after celery_app is created)
from . import tasks  # noqa: E402, F401
