# CHPL Patron Turns 18

This script utilizes the Sierra REST API endpoint, `put /v6/patrons/{id}` to modify patron records, adding a `message` to their account--prompting staff to ask patrons to sign an agreement to switch to an adult card after they have turned 18 years old.

This script will query for:

* patrons who have turned 18 years old since the last `script_run_date`
* patron does not already have an existing "turns 18 message" applied to their record, or has had one applied to their card in the past. This check allows for the script to play "catch-up" if it hasn't been run for some time.

The content of the body sent in the PUT request (`/v6/patrons/{id}`) will look like the following:

```python
{
    "varFields": [
    {
      "fieldTag": "m",
      "content": f"{datetime.now().strftime('%m/%d/%Y')} User turned 18.  Need agreement signed."
    }
  ]
}
```
