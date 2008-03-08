#!/bin/sh

echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<statuses type=\"array\">" > $SCREEN_NAME.xml;
for i in $SCREEN_NAME/*.xml; do sed 's/<?xml version="1.0" encoding="UTF-8"?>//' < $i >> $SCREEN_NAME.xml; done;
echo "</statuses>" >> $SCREEN_NAME.xml
