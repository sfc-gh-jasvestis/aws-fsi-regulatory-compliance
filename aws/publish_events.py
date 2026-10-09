"""Publish simulated surveillance events to Amazon Data Firehose (stream <prefix>-events).

Each event is a captured communication or a trade booking by a front-office employee.
Firehose batches the records into S3 (events/); Snowpipe loads them into RAW.LIVE_EVENTS.
Employee IDs come from RAW.EMPLOYEES (EMP-0000..EMP-0039). Values are seeded random.
"""
import argparse
import json
import random
import time
from datetime import datetime, timezone

CHANNELS = ('Email', 'Bloomberg chat', 'Recorded voice line', 'Approved mobile messaging', 'Trade booking')


def make_event(rng):
    alert = rng.random() < 0.1
    channel = rng.choice(CHANNELS)
    notional = round((2500000 if alert else 400000) * rng.lognormvariate(0, 0.5), 2) if channel == 'Trade booking' else 0
    return {'employee_id': f'EMP-{rng.randint(0, 39):04d}',
            'event_ts': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3],
            'channel': channel,
            'notional_sgd': notional,
            'flagged_terms': max(0, round((4 if alert else 0) + rng.gauss(0, 0.7))),
            'status': 'ALERT' if alert else 'OK',
            'sent_ms': int(time.time() * 1000)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--region', default='us-west-2')
    ap.add_argument('--prefix', default='sg-regcomp')
    ap.add_argument('--count', type=int, default=40)
    ap.add_argument('--seed', type=int)
    args = ap.parse_args()
    import boto3
    firehose = boto3.client('firehose', region_name=args.region)
    stream = f'{args.prefix}-events'
    rng = random.Random(args.seed)
    records = [{'Data': (json.dumps(make_event(rng)) + '\n').encode()} for _ in range(args.count)]
    for start in range(0, len(records), 500):
        out = firehose.put_record_batch(DeliveryStreamName=stream, Records=records[start:start + 500])
        if out['FailedPutCount']:
            raise RuntimeError(f"{out['FailedPutCount']} records were rejected by Firehose")
    print(f'published {args.count} surveillance events to Firehose stream {stream}; S3 delivery buffers up to 60 s')


if __name__ == '__main__':
    main()
