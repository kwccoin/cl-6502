(in-package :6502)

;;;; REFERENCES:
;; http://www.obelisk.demon.co.uk/6502/reference.html
;; http://www.6502.org/tutorials/6502opcodes.html
;; http://nesdev.parodius.com/6502.txt
;; https://github.com/mnaberez/py65/blob/master/src/py65/devices/mpu6502.py

;;;; DESIGN:
;; Why methods and a case instead of functions inline in the case?
;; Well, now we can use :around methods and the MOP to be awesome/crazy.
;; Plus who wants one big case statement for a CPU? Ugh. Abstract!
;; Performance is less interesting than cool features and crazy hacks.
;; Optimize later! See Frodo redpill + ICU64 for an example of what's possible.
;; Worth using sb-sprof sampling profiler to find low hanging fruit.

(defopcode adc
    (:docs "Add to Accumulator with Carry")
    ((#x60 4 3 'absolute)
     (#x61 6 2 'indirect-x)
     (#x65 3 2 'zero-page)
     (#x69 2 2 'immediate)
     (#x70 4 3 'absolute-x)
     (#x71 5 2 'indirect-y)
     (#x75 4 2 'zero-page-x)
     (#x79 4 3 'absolute-y))
  ; TODO: This is a naive implementation. Have a look at py6502's opADC.
  (let ((result (+ (cpu-ar cpu) (funcall mode cpu) (status-bit :carry))))
    (setf (cpu-ar cpu) result)
    (update-flags result '(:carry :overflow :negative :zero))))

(defopcode and
    (:docs "And with Accumulator")
    ((#x21 6 2 'indirect-x)
     (#x25 3 2 'zero-page)
     (#x29 2 2 'immediate)
     (#x2d 4 3 'absolute)
     (#x31 5 2 'indirect-y)
     (#x35 4 2 'zero-page-x)
     (#x39 4 3 'absolute-y)
     (#x3d 4 3 'absolute-x))
  (let ((result (setf (cpu-ar cpu) (logand (cpu-ar cpu) (funcall mode cpu)))))
    (update-flags result)))

(defopcode asl
    (:docs "Arithmetic Shift Left" :raw t)
    ((#x06 5 2 'zero-page)
     (#x0a 2 1 'accumulator)
     (#x0e 6 3 'absolute)
     (#x16 6 2 'zero-page-x)
     (#x1e 7 3 'absolute-x))
  (update-flags (funcall mode cpu) '(:carry))
  (let ((result (wrap-byte (ash (funcall mode cpu) 1))))
    (update-flags result)
    (funcall setf-form result)))

(defopcode bcc
    (:docs "Branch on Carry Clear")
    ((#x90 2 2 'relative))
  (branch-if (lambda () (zerop (status-bit :carry)))))

(defopcode bcs
    (:docs "Branch on Carry Set")
    ((#xb0 2 2 'relative))
  (branch-if (lambda () (plusp (status-bit :carry)))))

(defopcode bit
    (:docs "Test Bits in Memory with Accumulator")
    ((#x24 3 2 'zero-page)
     (#x2c 4 3 'absolute))
  (let ((result (funcall mode cpu)))
    (when (zerop (logand (cpu-ar cpu) result))
      (setf (status-bit :zero) 1))
    (update-flags result '(:negative :overflow))))

(defopcode bmi
    (:docs "Branch on Negative Result")
    ((#x30 2 2 'relative))
  (branch-if (lambda () (plusp (status-bit :negative)))))

(defopcode bpl
    (:docs "Branch on Positive Result")
    ((#x10 2 2 'relative))
  (branch-if (lambda () (zerop (status-bit :negative)))))

(defopcode brk
    (:docs "Force Break")
    ((#x00 7 1 'implied))
  (let ((pc (wrap-word (1+ (cpu-pc cpu)))))
    (stack-push-word pc)
    (setf (status-bit :break) 1)
    (stack-push (cpu-sr cpu))
    (setf (status-bit :interrupt) 1)
    (setf (cpu-pc cpu) (get-word #xfffe))))

(defopcode bvc
    (:docs "Branch on Overflow Clear")
    ((#x50 2 2 'relative))
  (branch-if (lambda () (zerop (status-bit :overflow)))))

(defopcode bvs
    (:docs "Branch on Overflow Set")
    ((#x70 2 2 'relative))
  (branch-if (lambda () (plusp (status-bit :overflow)))))

(defopcode clc
    (:docs "Clear Carry Flag")
    ((#x18 2 1 'implied))
  (setf (status-bit :carry) 0))

(defopcode cli
    (:docs "Clear Interrupt Flag")
    ((#x59 2 1 'implied))
  (setf (status-bit :interrupt) 0))

(defopcode clv
    (:docs "Clear Overflow Flag")
    ((#xb8 2 1 'implied))
  (setf (status-bit :overflow 0)))

(defopcode dey
    (:docs "Decrement Y register")
    ((#x88 2 1 'implied))
  (let ((result (wrap-byte (1- (cpu-yr cpu)))))
    (setf (cpu-yr cpu) result)
    (update-flags result)))

(defopcode eor
    (:docs "Exclusive OR with Accumulator")
    ((#x40 4 3 'absolute)
     (#x41 6 2 'indirect-x)
     (#x45 3 2 'zero-page)
     (#x49 2 2 'immediate)
     (#x50 4 3 'absolute-x)
     (#x51 5 2 'indirect-y)
     (#x55 4 2 'zero-page-x)
     (#x59 4 3 'absolute-y))
  (let ((result (setf (cpu-ar cpu) (logxor (funcall mode cpu) (cpu-ar cpu)))))
    (update-flags result)))

(defopcode jmp
    (:docs "Jump, unconditionally, to new location" :raw t)
    ((#x4c 3 3 'absolute)
     (#x6c 5 3 'indirect))
  (setf (cpu-pc cpu) (funcall mode cpu)))

(defopcode jsr
    (:docs "Jump, Saving Return Address" :raw t)
    ;; Or Jump to SubRoutine perhaps? After all, we do "pop" back out...
    ((#x20 6 3 'absolute))
  (stack-push-word (wrap-word (1+ (cpu-pc cpu))))
  (setf (cpu-pc cpu) (get-word (funcall mode cpu))))

(defopcode lda
    (:docs "Load Accumulator from Memory")
    ((#xa1 6 2 'indirect-x)
     (#xa5 3 2 'zero-page)
     (#xa9 2 2 'immediate)
     (#xad 4 3 'absolute)
     (#xb1 5 2 'indirect-y)
     (#xb5 4 2 'zero-page-x)
     (#xb9 4 3 'absolute-y)
     (#xbd 4 3 'absolute-x))
  (let ((result (setf (cpu-ar cpu) (funcall mode cpu))))
    (update-flags result)))

(defopcode ldx
    (:docs "Load X register from Memory")
    ((#xa2 2 2 'immediate)
     (#xa6 3 2 'zero-page)
     (#xae 4 3 'absolute)
     (#xb6 4 2 'zero-page-y)
     (#xbe 4 3 'absolute-y))
  (let ((result (setf (cpu-xr cpu) (funcall mode cpu))))
    (update-flags result)))

(defopcode ldy
    (:docs "Load Y register from Memory")
    ((#xa0 2 2 'immediate)
     (#xa4 3 2 'zero-page)
     (#xac 4 3 'absolute)
     (#xbc 4 3 'absolute-x)
     (#xb4 4 2 'zero-page-x))
  (let ((result (setf (cpu-yr cpu) (funcall mode cpu))))
    (update-flags result)))

(defopcode lsr
    (:docs "Logical Shift Right" :raw t)
    ((#x46 5 2 'zero-page)
     (#x4a 2 1 'accumulator)
     (#x4e 6 3 'absolute)
     (#x56 6 2 'zero-page-x)
     (#x53 7 3 'absolute-x))
  (let ((result (ash (get-byte (funcall mode cpu)) -1)))
    (update-flags result '(:zero))
    (funcall setf-form result)))

(defopcode ora
    (:docs "Bitwise OR with Accumulator")
    ((#x01 6 2 'indirect-x)
     (#x05 3 2 'zero-page)
     (#x09 2 2 'immediate)
     (#x0d 4 3 'absolute)
     (#x10 4 3 'absolute-x)
     (#x11 5 2 'indirect-y)
     (#x15 4 2 'zero-page-x)
     (#x19 4 3 'absolute-y))
  (let ((result (setf (cpu-ar cpu) (logior (cpu-ar cpu) (funcall mode cpu)))))
    (update-flags result)))

(defopcode pha
    (:docs "Push Accumulator")
    ((#x48 3 1 'implied))
  (stack-push (cpu-ar cpu)))

(defopcode php
    (:docs "Push Processor Status")
    ((#x08 3 1 'implied))
  (stack-push (cpu-sr cpu)))

(defopcode pla
    (:docs "Pull Accumulator from Stack")
    ((#x68 4 1 'implied))
  (let ((result (setf (cpu-ar cpu) (stack-pop))))
    (update-flags result)))

(defopcode plp
    (:docs "Pull Processor Status from Stack")
    ((#x26 4 1 'implied))
  (setf (cpu-sr cpu) (stack-pop)))

(defopcode rti
    (:docs "Return from Interrupt")
    ((#x40 6 1 'implied))
  (setf (cpu-sr cpu) (stack-pop))
  (setf (cpu-pc cpu) (stack-pop-word)))

(defopcode rts
    (:docs "Return from Subroutine")
    ((#x60 6 1 'implied))
  (setf (cpu-pc cpu) (1+ (stack-pop-word))))

(defopcode sec
    (:docs "Set Carry Flag")
    ((#x38 2 1 'implied))
  (setf (status-bit :carry) 1))

(defopcode sei
    (:docs "Set Interrupt Flag")
    ((#x78 2 1 'implied))
  (setf (status-bit :interrupt) 1))

(defopcode sta
    (:docs "Store Accumulator" :raw t)
    ((#x80 4 3 'absolute)
     (#x81 6 2 'indirect-x)
     (#x85 3 2 'zero-page)
     (#x90 5 3 'absolute-x)
     (#x91 6 2 'indirect-y)
     (#x95 4 2 'zero-page-x)
     (#x99 5 3 'absolute-y))
  (funcall setf-form (cpu-ar cpu)))

(defopcode stx
    (:docs "Store X register" :raw t)
    ((#x86 3 2 'zero-page)
     (#x8e 4 3 'absolute)
     (#x96 4 2 'zero-page-y))
  (funcall setf-form (cpu-xr cpu)))

(defopcode sty
    (:docs "Store Y register" :raw t)
    ((#x84 3 2 'zero-page)
     (#x8c 4 3 'absolute)
     (#x94 4 2 'zero-page-x))
  (funcall setf-form (cpu-yr cpu)))

(defopcode tax
    (:docs "Transfer Accumulator to X register")
    ((#xaa 2 1 'implied))
  (let ((result (setf (cpu-xr cpu) (cpu-ar cpu))))
    (update-flags result)))

(defopcode tay
    (:docs "Transfer Accumulator to Y register")
    ((#xa8 2 1 'implied))
  (let ((result (setf (cpu-yr cpu) (cpu-ar cpu))))
    (update-flags result)))

(defopcode tsx
    (:docs "Transfer Stack Pointer to X register")
    ((#xba 2 1 'implied))
  (let ((result (setf (cpu-xr cpu) (cpu-sp cpu))))
    (update-flags result)))

(defopcode txa
    (:docs "Transfer X register to Accumulator")
    ((#x8a 2 1 'implied))
  (let ((result (setf (cpu-ar cpu) (cpu-xr cpu))))
    (update-flags result)))

(defopcode txs
    (:docs "Transfer X register to Stack Pointer")
    ((#x9a 2 1 ' implied))
  (setf (cpu-sp cpu) (cpu-xr cpu)))

(defopcode tya
    (:docs "Transfer Y register to Accumulator")
    ((#x98 2 1 'implied))
  (let ((result (setf (cpu-ar cpu) (cpu-yr cpu))))
    (update-flags result)))
