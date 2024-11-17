import hypersync
from hypersync import TransactionField, ClientConfig, Query, TransactionSelection, FieldSelection, StreamConfig
import asyncio

FILE_PATH = "addr.data"

async def main(): 
    client = hypersync.HypersyncClient(ClientConfig())

    query = Query(
        from_block=0,
        transactions=[TransactionSelection()],
        field_selection=FieldSelection(
            transaction=[
                TransactionField.FROM,
                TransactionField.TO,
            ]
        ),
    )

    receiver = await client.stream(query, StreamConfig())

    addrs = []

    file = open(FILE_PATH, 'w')

    while True:
        res = await receiver.recv()

        if res is None:
            break

        for tx in res.data.transactions:
            from_ = tx.from_ 
            to = tx.to
            if from_ is not None:
                addrs.append(from_)
            if to is not None:
                addrs.append(to)

        if len(addrs) > 1000: 
            for addr in addrs:
                file.write(addr);

            addrs = []

    file.close()

asyncio.run(main())
