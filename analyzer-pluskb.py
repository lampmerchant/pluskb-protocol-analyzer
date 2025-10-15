from collections import deque
from datetime import datetime
import sys

import serial


COMMANDS = {
  0x10: ('Inquiry', {0x7B: 'Null', None: ''}),
  0x14: ('Instant', {0x7B: 'Null', None: ''}),
  0x16: ('Model Number', {None: ''}),
  0x36: ('Test', {0x77: 'NAK', 0x7D: 'ACK', None: 'Unknown'}),
  None: ('Unknown', {None: ''}),
}


class KeyboardAnalyzer:
  '''Represents a serial keyboard analyzer.'''
  
  def __init__(self, serial_obj):
    self.serial_obj = serial_obj
  
  def run(self):
    
    last_str = None
    last_count = 0
    queue = deque()
    
    while True:
      
      byte = self.serial_obj.read(1)
      if byte == b'': continue
      byte = byte[0]
      queue.append(byte)
      if len(queue) < 2: continue
      
      command = bytes(queue)
      command_str, response_strs = COMMANDS.get(command[0], COMMANDS[None])
      command_str = '0x%02X%s' % (command[0], f' ({command_str})' if command_str else '')
      if command[1] & 0x01 and not command[0] & 0x01:
        response_str = response_strs.get(command[1], response_strs[None])
        response_str = '0x%02X%s' % (command[1], f' ({response_str})' if response_str else '')
        command_str = f'{command_str} ?  {response_str} !'
        queue.clear()
      elif not command[0] & 0x01:
        command_str = f'{command_str} ?'
        queue.popleft()
      else:
        command_str = '0x%02X' % command[0]
        queue.popleft()
      
      if command_str == last_str:
        last_count += 1
      else:
        if last_str is not None and last_count > 1:
          sys.stdout.write('  x %d\n' % last_count)
        else:
          sys.stdout.write('\n')
        last_str = command_str
        last_count = 1
        sys.stdout.write(datetime.now().strftime('(%H:%M:%S) '))
        sys.stdout.write(command_str)
        sys.stdout.flush()
