#!/bin/sh

echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<statuses type=\"array\">"
for i in $SCREEN_NAME/*.xml; do sed 's/<?xml version="1.0" encoding="UTF-8"?>//' < $i; done;
echo "</statuses>"
