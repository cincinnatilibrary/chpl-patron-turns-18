# !pip install -U sqlalchemy
# !pip install -U psycopg2-binary
# !pip install -U requests

# !pip freeze > requirements.txt

# set up the logging
# https://docs.python.org/3.7/howto/logging-cookbook.html#using-a-rotator-and-namer-to-customize-log-rotation-processing
# https://docs.python.org/3/howto/logging-cookbook.html#using-a-rotator-and-namer-to-customize-log-rotation-processing
import gzip
import logging
import logging.handlers
import os
import shutil

def namer(name):
    return name + ".gz"

def rotator(source, dest):
    with open(source, 'rb') as f_in:
        with gzip.open(dest, 'wb') as f_out:
            shutil.copyfileobj(f_in, f_out)
    os.remove(source)

rh = logging.handlers.RotatingFileHandler(
    'turns18.log',
    maxBytes=524288, 
    backupCount=3
)
rh.rotator = rotator
rh.namer = namer

root = logging.getLogger()
root.setLevel(logging.INFO)
root.addHandler(rh)
f = logging.Formatter('%(asctime)s %(name)s %(levelname)s %(message)s')
rh.setFormatter(f)

logging.info('Script Started')


# sierraAPI are helper functions for the REST API
import sierraAPI
import json
import requests
from sqlalchemy import create_engine, text
from datetime import datetime



# read the configuration file
config_file = 'config.json'
logging.info(f"config_file: {config_file}")

try:
    with open(config_file, "r") as f:
        config = json.load(f)

    client_key = config["client_key"]
    client_secret = config["client_secret"]
    base_url = config["base_url"]
    db_connection_string = config["db_connection_string"]
    logging.info(f"base_url: {base_url}")

except:
    logging.error('error opening config.json')
    exit()



# connect to the Sierra DB
try:
    sierra_engine = create_engine(db_connection_string)
    # print(f"sierra_engine.url: {sierra_engine.url}")

except:
    logging.error('error connecting to Sierra DB')
    exit()

# get the header for API authorization
try:
    headers = sierraAPI.get_access_headers(
        client_key=client_key,
        client_secret=client_secret,
        base_url=base_url
    )

    r = requests.get(base_url + 'info/token', headers=headers, verify=True)
    logging.info(f"token expires in: {r.json()['expiresIn']}")

except:
    logging.error(f"Could not get API authorization: {r.text}")
    exit()



# get relevant information related to patrons who have turned 18 on this date
sql = """\
SELECT
    rm.record_num as patron_record_num,
    pr.ptype_code,
    pr.expiration_date_gmt::date as expiration_date,
    CASE
        when now()::date >= pr.expiration_date_gmt::date THEN TRUE
        else FALSE
    END AS is_expired,
    (
        select
            v.field_content
        from
            sierra_view.varfield as v
        where
            v.record_id = rm.id
            and v.varfield_type_code = 'b'
        order by
            v.occ_num
        limit
            1
    ) as barcode
FROM
    sierra_view.record_metadata as rm
    join sierra_view.patron_record as pr on (
        pr.record_id = rm.id
        and pr.ptype_code in (
            0 , 1 , 2 , 5 , 6 , 7 , 30 , 31 , 32
        )
        and (pr.birth_date_gmt + interval '18 years')::date = now()::date
    )
WHERE
    rm.record_type_code = 'p'
    and rm.campus_code = ''
"""



with sierra_engine.connect() as connection:
    try:
        result = connection.execute(text(sql))
    except:
        logging.error('Could not execute sql')
        exit()
        
    for i, row in enumerate(result):
        try:
            # print(f"row['is_expired']: {row['is_expired']}")
            # this is the data we'll patch to the patron record
            # NOTE: set, `expirationDate` to current date if the patron has is_expired == FALSE
            # ... otherwise, keep the old expiration date
            if row['is_expired'] is False:
                # update the expirationDate
                json = {
                    "expirationDate": datetime.now().strftime('%Y-%m-%d'),
                    "varFields": [
                        {
                            "fieldTag": "m",
                            "content": f"{datetime.now().strftime('%m/%d/%Y')} User turned 18.  Need agreement signed."
                        }
                      ]
                }
            else:
                # don't update the expirationDate
                json = {
                    "varFields": [
                        {
                            "fieldTag": "m",
                            "content": f"{datetime.now().strftime('%m/%d/%Y')} User turned 18.  Need agreement signed."
                        }
                      ]
                }
            # create the URL for the REST API
            url=f"{base_url}patrons/{row['patron_record_num']}"

            # perform the API request
            # print(row['expiration_date'], json)
            r = requests.put(
                url=url,
                headers=headers,
                json=json
            )
            logging.info(f"{i} PUT: {url} patron_data: {row} status_code: {r.status_code}")
        
        except:
            logging.error(f"Could not patch patron: {row['patron_record_num']}")



logging.info('Script Finished')
