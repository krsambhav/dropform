import Foundation

enum EmailExtraction {
    // Python's standard-library MIME parser handles encodings and multipart messages.
    // HTML is reduced to text, so exporting an email never loads remote content.
    static let script = #"""
import sys
from email import policy
from email.parser import BytesParser
from html.parser import HTMLParser
class Text(HTMLParser):
    def __init__(self):
        super().__init__(); self.parts=[]; self.hidden=0
    def handle_starttag(self, tag, attrs):
        if tag in ('script','style'): self.hidden += 1
        if tag in ('p','div','br','li','tr','h1','h2','h3'): self.parts.append('\n')
    def handle_endtag(self, tag):
        if tag in ('script','style'): self.hidden=max(0,self.hidden-1)
        if tag in ('p','div','li','tr'): self.parts.append('\n')
    def handle_data(self, data):
        if not self.hidden: self.parts.append(data)
with open(sys.argv[1], 'rb') as f: message=BytesParser(policy=policy.default).parse(f)
body=message.get_body(preferencelist=('plain','html'))
if body is None: raise ValueError('This email has no readable text body.')
content=body.get_content()
if body.get_content_type() == 'text/html':
    parser=Text(); parser.feed(content); content=''.join(parser.parts)
headers=['%s: %s' % (key, str(message[key])) for key in ('Subject','From','To','Cc','Date') if message[key]]
attachments=[part.get_filename() or 'Unnamed attachment' for part in message.iter_attachments()]
result='\n'.join(headers)+'\n\n'+content
if attachments: result+='\n\nAttachments (not extracted):\n'+'\n'.join(attachments)
with open(sys.argv[2], 'w', encoding='utf-8') as f: f.write(result)
"""#
}
