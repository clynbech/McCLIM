;;; -*- Mode: Lisp; Package: GOATEE -*-

;;;  (c) copyright 2002 by Tim Moore (moore@bricoworks.com)
;;; This library is free software; you can redistribute it and/or
;;; modify it under the terms of the GNU Library General Public
;;; License as published by the Free Software Foundation; either
;;; version 2 of the License, or (at your option) any later version.
;;;
;;; This library is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; Library General Public License for more details.
;;;
;;; You should have received a copy of the GNU Library General Public
;;; License along with this library; if not, write to the 
;;; Free Software Foundation, Inc., 59 Temple Place - Suite 330, 
;;; Boston, MA  02111-1307  USA.

(in-package :goatee)

(defclass location ()
  ((line :accessor line :initarg :line)
   (pos :accessor pos :initarg :pos))
  (:documentation "A location in a buffer."))

(defmethod location* ((bp location))
  (values (line bp) (pos bp)))

(defgeneric* (setf location*) (line pos bp))

(defmethod* (setf location*) (line pos (bp location))
  (setf (values (line bp) (pos bp)) (values line pos)))

;;; basic-buffer must implement:
;;; lines
;;; tick
;;; size
;;; buffer-insert*
;;; buffer-delete-char*
;;; buffer-open-line*
;;; buffer-close-line*

(defclass basic-buffer ()
  ())

(defclass basic-buffer-mixin (basic-buffer)
  ((lines :accessor lines :initarg :lines
	  :initform (make-instance 'dbl-list-head))
   (tick :accessor tick :initarg :tick :initform 0)
   (point :accessor point :documentation "A buffer-pointer that
  maintains the current insertion point.")
   (size :reader size :initform 0)))

(define-condition buffer-bounds-error (goatee-error)
  ((buffer :reader buffer-bounds-error-buffer :initarg :buffer :initform nil)
   (line :reader buffer-bounds-error-line :initarg :line :initform nil)
   (pos :reader buffer-bounds-error-pos :initarg :pos :initform nil))
  (:report (lambda (condition stream)
	     (format stream "In buffer ~S, position line ~S pos ~S is ~
                             out of bounds"
		     (buffer-bounds-error-buffer condition)
		     (buffer-bounds-error-line condition)
		     (buffer-bounds-error-pos condition)))))


;;; A moment of convenience, a lifetime of regret...

(defmethod point* ((buf basic-buffer-mixin))
  (let ((point (point buf)))
    (values (line point) (pos point))))

(defgeneric* (setf point*) (line pos buffer))

(defmethod* (setf point*) (line pos (buf basic-buffer-mixin))
  (let ((point (slot-value buf 'point)))
    ;; If there's a next line, the point can't be moved past the
    ;; newline at the end of the line.
    (when (and (next line)
	       (> pos (1- (size line))))
      (error 'buffer-bounds-error :buffer buf :line line :pos pos))
    (when (not (eq (line point) line))
      (setf (tick line) (incf (tick buf))))
    (setf (location* point) (values line pos))
    (setf (tick (line point)) (incf (tick buf)))
    (values line pos)))


(defclass buffer-line (flexivector dbl-list)
  ((buffer :accessor buffer :initarg :buffer)
   (tick :accessor tick :initarg :tick :initform 0)))

(defgeneric make-buffer-line (buffer &rest initargs)
  (:documentation "Creates line instances for a buffer"))

(defmethod make-buffer-line ((buffer basic-buffer-mixin) &rest initargs)
  (apply #'make-instance 'buffer-line :buffer buffer initargs))

(defmethod initialize-instance :after ((obj basic-buffer-mixin) &key)
  (dbl-insert-after (make-buffer-line obj :tick (incf (tick obj))) (lines obj))
  (setf (point obj) (make-instance 'location
				   :line (dbl-head (lines obj))
				   :pos 0)))

(defgeneric char-ref (buffer position))

(defmethod char-ref ((buf basic-buffer) position)
  (char-ref (line position) (pos position)))

(defmethod char-ref* ((buf basic-buffer) line pos)
  (char-ref line pos))

(defgeneric buffer-open-line* (buffer line pos)
  (:documentation "Insert a newline at POS in LINE, creating a new line that
  contains LINEs contents from POS to the end of LINE.  Returns the position
  (spread) of the beginning of the new line"))

(defmethod buffer-open-line*
    ((buf basic-buffer-mixin) (line buffer-line) pos)
  (let ((len (size line)))
    (if (<= pos len)			;XXX throw an error?
	(let ((new-line (make-buffer-line
			 buf
			 :buffer buf
			 :initial-store (flexivector-string line :start pos)
			 :tick (incf (tick buf)))))
	  ;; delete to end of line
	  (delete-char line (- (size line) pos) :position pos)
	  (insert line #\newline :position pos)
	  (setf (tick line) (incf (tick buf)))
	  (dbl-insert-after new-line line)
	  (incf (slot-value buf 'size))
	  (values new-line 0))
	(error 'buffer-bounds-error :buffer buf :line line :pos pos))))

(defgeneric buffer-insert* (buffer thing line pos &key))

(defmethod buffer-insert* ((buffer basic-buffer-mixin) (c character) line pos
			   &key)
  (when (or (> pos (line-last-point line))
	    (< pos 0))
    (error 'buffer-bounds-error :buffer buffer :line line :pos pos))
  (insert line c :position pos)
  (incf (slot-value buffer 'size))
  (setf (tick line) (incf (tick buffer)))
  (values line (1+ pos)))

(defmethod buffer-insert* ((buffer basic-buffer-mixin) (s string) line pos
			   &key (start 0) (end (length s)))
  (when (or (> pos (line-last-point line))
	    (< pos 0))
    (error 'buffer-bounds-error :buffer buffer :line line :pos pos))
  (let ((len (- end start)))
    (insert line s :position pos :start start :end end)
    (incf (slot-value buffer 'size) len)
    (setf (tick line) (incf (tick buffer)))
    (values line (+ pos len))))

;;; Insert is the convenience function; thing can contain newline(s).
;;;
;;; Soon insert, delete-char et al. won't need to maintain the point; should
;;; they set it at all?

(defmethod insert ((buffer basic-buffer) (c character)
		   &key position line (pos 0))
  (cond (position
	 (setf (point buffer) position))
	(line
	 (setf (point* buffer) (values line pos))))
  (let* ((pt (slot-value buffer 'point))
	 (line (line pt))
	 (pos (pos pt)))
    (setf (location* pt)
	  (if (eql c #\Newline)
	      (buffer-open-line* buffer line pos)
	      (buffer-insert* buffer c line pos)))
    nil))

(defmethod insert ((buffer basic-buffer) (s string)
		   &key position line (pos 0) (start 0) (end (length s)))
  (cond (position
	 (setf (point buffer) position))
	(line
	 (setf (point* buffer) (values line pos))))
  (multiple-value-bind (line pos)
      (point* buffer)
    (loop for search-start = start then (1+ found-newline)
	  for found-newline = (position #\Newline s
					:start search-start
					:end end)
	  while found-newline
	  do (progn
	       (setf (values line pos)
		     (buffer-insert* buffer s line pos
				     :start search-start
				     :end found-newline))
	       (setf (values line pos)
		     (buffer-open-line* buffer line pos)))
	  finally (setf (values line pos)
			(buffer-insert* buffer s line pos
					:start search-start :end end)))
    (setf (point* buffer) (values line pos)))
  nil)

(defgeneric buffer-close-line* (buffer line direction)
  (:documentation "If DIRECTION is positive, delete the newline at the
  end of line, bring the following line's contents onto line, and
  delete the following line.  If DIRECTION is negative, first move back
  one line, then do the deletion." ))

(defmethod buffer-close-line* ((buffer basic-buffer-mixin) line direction)
  (multiple-value-bind (this-line next-line)
      (if (< 0 direction)
	  (values line (next line))
	  (values (prev line) line))
    (unless (typep this-line 'dbl-list)
      (error 'buffer-bounds-error :buffer buffer :line nil :pos 0))
    (let ((line-size (size this-line)))
      (if (eql (char-ref line (1- line-size)) #\Newline)
	  (progn
	    (delete-char line 1 :position (1- line-size))
	    (decf (slot-value buffer 'size))
	    (when next-line
	      (loop for i from 0 below (size next-line)
		    for j from (1- line-size)
		    do (insert this-line (char-ref next-line i) :position j))
	      (dbl-remove next-line))
	    (setf (tick this-line) (incf (tick buffer)))
	    (values this-line (1- line-size)))
	  (error 'buffer-bounds-error
		 :buffer buffer :line line :pos line-size)))))

(defgeneric buffer-delete-char* (buffer line pos n)
  (:documentation "Delete characters from a line.  Can not delete the final
  newline or characters before the beginning of the line"))

(defmethod buffer-delete-char* ((buffer basic-buffer-mixin) line pos n)
  (multiple-value-prog1
        (if (>= n 0)
	    (progn
	      (when (> (+ pos n) (line-last-point line))
		(error 'buffer-bounds-error :buffer buffer :line line :pos pos))
	      (delete-char line n :position pos)
	      (decf (slot-value buffer 'size) n)
	      (values line pos))
	    (progn
	      (when (< (+ pos n) 0)
		(error 'buffer-bounds-error :buffer buffer :line line :pos pos))
	      (delete-char line n :position pos)
	      (incf (slot-value buffer 'size) n)
	      (values line (+ pos n))))
    (setf (tick line) (incf (tick buffer)))))

(defmethod delete-char ((buf basic-buffer) &optional (n 1)
			&key position line (pos 0))
  (cond (position
	 (setf (point buf) position))
	(line
	 (setf (point* buf) (values line pos))))
  (multiple-value-bind (line pos)
      (point* buf)
    (if (>= n 0)
	(loop with remaining = n
	      for last-point = (line-last-point line)
	      while (> (+ remaining pos) last-point)
	      do (let ((del-chars (- last-point pos)))
		   (when (> del-chars 0)
		     (buffer-delete-char* buf line pos (1- del-chars)))
		   ;; Up against the end, this should signal an error
		   (setf (values line pos) (buffer-close-line* buf line 1)) 
		   (decf remaining (1+ del-chars)))
	    finally (setf (values line pos)
		          (buffer-delete-char* buf line pos remaining)))
	(loop with remaining = (- n)
	      while (< (- pos remaining) 0)
	      do (progn
		   (buffer-delete-char* buf line pos (- pos))
		   (decf remaining pos)
		   (setf (values line pos)
			 (buffer-close-line* buf line -1)))
	      finally (setf (values line pos)
			    (buffer-delete-char* buf line pos (- remaining)))))
    (setf (point* buf) (values line pos)))
  nil)

(defun adjust-fill (array new-fill)
  (if (> new-fill (car (array-dimensions array)))
      (adjust-array array new-fill :fill-pointer new-fill)
      (setf (fill-pointer array) new-fill))
  array)

(defgeneric buffer-string (buffer &key start end))

(defmethod buffer-string ((buf basic-buffer) &key start end result)
  (declare (ignore start end))
  (let ((result (if result
		    (adjust-fill result (size buf))
		    (make-string (size buf)))))
    (loop for line-in-string = 0 then (+ line-in-string (size line))
	  for line = (dbl-head (lines buf)) then (next line)
	  while line
	  do (flexivector-string-into line result :start1 line-in-string))
    result))

(defun line-last-point (line)
  "Returns the last legal value for a position on a line, which is either
  before the newline, if there is one, or after the last character."
  (let* ((size (size line))
	 (last-char (if (> size 0)
			(char-ref line (1- size))
			nil)))
    (cond ((and last-char (char= last-char #\Newline))
	   (1- size))
	  (t size))))

(defmethod forward-char* ((buf basic-buffer) n
			  &key (position (point buf)) line (pos 0))
  (multiple-value-bind (line pos)
      (if line
	  (values line pos)
	  (location* position))
    (if (>= n 0)
	(loop for current-line = line then (next current-line)
	      for current-pos = pos then 0
	      for current-line-size = (or (and current-line (size current-line))
					  0)
	      for ends-in-nl = (and current-line
				    (char= (char-ref current-line
						     (1-
						      current-line-size))
					   #\Newline))
	      for chars-to-eol = (- current-line-size
				    (if ends-in-nl 1 0)
				    current-pos)
	      ;; point goes before #\newline, then to the next line.
	      for remaining = n then (- remaining chars-to-eol)
	      until (or (null current-line) (<= remaining chars-to-eol))
	      finally (if (null current-line)
			  (error 'buffer-bounds-error :buffer buf)
			  (return (values current-line
					  (+ current-pos remaining)))))
	(loop for current-line = line then (and (prev current-line)
					      (typep (prev current-line)
						       'dbl-list))
	      for current-line-size = (or (and current-line (size current-line))
					  0)
	      for current-pos = pos then (1- current-line-size)
	      for remaining = (- n) then (- remaining current-pos)
	      until (and current-line (<= remaining current-pos))
	      finally (if (null current-line)
			  (error 'buffer-bounds-error :buffer buf)
			  (return (values current-line
					  (- current-pos remaining))))))))

(defmethod forward-char ((buf basic-buffer) n &rest key-args)
  (multiple-value-bind (new-line new-pos)
      (apply #'forward-char* buf n key-args)
    (make-instance 'location :line new-line :pos new-pos)))

(defgeneric end-of-line* (buffer &key position line pos))

(defgeneric end-of-line (buffer &rest key-args))

(defmethod end-of-line* ((buf basic-buffer)
			 &key (position (point buf)) line (pos 0))
  (multiple-value-bind (line pos)
      (if line
	  (values line pos)
	  (location* position))
    (values line (line-last-point line))))

(defmethod end-of-line ((buf basic-buffer) &rest key-args)
  (multiple-value-bind (new-line new-pos)
      (apply #'end-of-line* buf key-args)
    (make-instance 'location :line new-line :pos new-pos)))

(defgeneric beginning-of-line* (buffer &key position line pos))

(defmethod beginning-of-line* ((buf basic-buffer)
			       &key (position (point buf)) line (pos 0))
  (multiple-value-bind (line pos)
      (if line
	  (values line pos)
	  (location* position))
    (values line 0)))

;;; The need for these should go away once we have real buffer pointers...

(defmethod beginning-of-buffer* ((buf basic-buffer))
  (values (dbl-head (lines buf))
	  0))

(defmethod end-of-buffer* ((buf basic-buffer))
  (loop for line = (dbl-head (lines buf)) then (next line)
	while (next line)
	finally (return (end-of-line* buf :line line))))

;;; Buffer pointers and the bp-buffer-mixin that maintains them.

(defclass bp-buffer-mixin ()
  ())

(defclass bp-buffer-line (buffer-line)
  ((bps :accessor bps :initarg :bps :initform nil)))

(defmethod make-buffer-line ((buffer bp-buffer-mixin) &rest initargs)
  (apply #'make-instance 'bp-buffer-line :buffer buffer initargs))

(defclass buffer-pointer (location)
  ()
  (:documentation "Buffer pointer that moves with insertions at its location"))

(defmethod initialize-instance :after ((obj buffer-pointer) &key)
  (when (slot-boundp obj 'line)
    (push obj (bps (line obj)))))

(defmethod (setf line) (new-line (bp buffer-pointer))
  (when (slot-boundp bp 'line)
    (setf (bps (line bp)) (delete bp (bps (line bp))))
    (prog1
	(call-next-method)
      (when new-line
	(push bp (bps (line bp)))))))

(defgeneric update-for-insert (bp pos delta))

(defmethod update-for-insert ((bp buffer-pointer) pos delta)
  (when (>= (pos bp) pos)
    (incf (pos bp) delta)))

(defclass fixed-buffer-pointer (buffer-pointer)
  ()
  (:documentation "Buffer pointer that doesn't move with insertions at its location"))

(defmethod update-for-insert ((bp fixed-buffer-pointer) pos delta)
  (when (> (pos bp) pos)
    (incf (pos bp))))

(defmethod buffer-insert* :after
    ((buffer basic-buffer-mixin) (c character) line pos &key)
  (loop for bp in (bps line)
	do (update-for-insert bp pos 1)))
  
(defmethod buffer-insert* :after
    ((buffer basic-buffer-mixin) (s string) line pos
     &key (start 0) (end (length s)))
  (loop with len = (- end start)
	for bp in (bps line)
	do (update-for-insert bp pos len)))

(defmethod buffer-delete-char* :after ((buffer bp-buffer-mixin) line pos n)
  (cond ((> n 0)
	 (loop for bp in (bps line)
	       when (> (pos bp) pos)
	       do (setf (pos bp) (max pos (- (pos bp) n)))))
	((< n 0)
	 (loop with new-pos = (+ pos n)
	       for bp in (bps line)
	       do (cond ((>= (pos bp) pos)
			 (incf (pos bp) n))
			((> (pos bp) new-pos)
			 (setf (pos bp) new-pos)))))))

(defmethod buffer-open-line* :around
    ((buf bp-buffer-mixin) (line bp-buffer-line) pos)
  (multiple-value-bind (new-line new-pos)
      (call-next-method)
    (loop for bp in (bps line)
	  if (typecase bp
	       (fixed-buffer-pointer
		(> (pos bp) pos))
	       (t (>= (pos bp) pos)))
	    do (setf (line bp) new-line
		     (pos bp) (- (pos bp) pos))
	    and collect bp into new-line-bps
	  else
	    collect bp into old-line-bps
	  end
	  finally (setf (bps line) old-line-bps
			(bps new-line) new-line-bps))
    (values new-line new-pos)))

(defmethod buffer-close-line* :around
    ((buffer bp-buffer-mixin) (line bp-buffer-line) direction)
  (multiple-value-bind (this-line next-line)
      (if (< 0 direction)
	  (values line (next line))
	  (values (prev line) line))
    (multiple-value-bind (line new-pos)
	(call-next-method)
      (loop for bp in (bps next-line)
	    do (progn
		 (incf (pos bp) new-pos)
		 (setf (line bp) this-line)
		 (push bp (bps this-line))))
      (values line new-pos))))

;;; In the next go-around, this will have buffer pointers, including the point
;;;which will be auto-updated.

(defclass editable-buffer (bp-buffer-mixin basic-buffer-mixin)
  ((buffer-start :accessor buffer-start
		 :documentation "A fixed buffer pointer at the start of the buffer.")
   (buffer-end :accessor buffer-end
	       :documentation "A buffer pointer at the end of the buffer.")))

(defmethod initialize-instance :after ((obj editable-buffer)
				       &key initial-contents
				       (start 0)
				       (end (when initial-contents
					      (length initial-contents))))
  (setf (buffer-start obj) (make-instance 'fixed-buffer-pointer
					  :line (dbl-head (lines obj))
					  :pos 0))
  (setf (buffer-end obj) (make-instance 'buffer-pointer
				     :line (dbl-head (lines obj))
				     :pos 0))
  (when initial-contents
    (insert obj initial-contents :start start :end end)))

(defmacro with-buffer-pointer* ((bp-var line pos &key (class ''buffer-pointer))
				&body body)
  "Like with-buffer-pointer, but takes line and pos as initialization
  arguments."
  (let ((bp-temp (gensym)))
     `(let* ((,bp-temp (make-instance ,class :line ,line :pos ,pos))
	     (,bp-var ,bp-temp))
	(unwind-protect
	     (progn
	       ,@body)
	  (setf (line ,bp-temp) nil)))))

(defmacro with-buffer-pointer ((bp-var location &key (class ''buffer-pointer))
			       &body body)
  "binds bp-var to a buffer pointer initialized to location.  Class is the
   class of the buffer pointer, defaulting to 'buffer-pointer. bp-var is
   deallocated when at exit from the form."
  (let ((line-var (gensym "LINE"))
	(pos-var (gensym "POS")))
     `(multiple-value-bind (,line-var ,pos-var)
	  (location* ,location)
       (with-buffer-pointer* (,bp-var ,line-var ,pos-var :class ,class)
	 ,@body))))

(defmacro with-point ((buffer) &body body)
  "Saves and restores the point of buffer around body."
  (let ((bp-var (gensym "BP"))
	(buffer-var (gensym "BUFFER")))
    `(let ((,buffer-var ,buffer))
       (with-buffer-pointer (,bp-var (point ,buffer-var))
	 (unwind-protect
	      (progn
		,@body)
	   (setf (location* (point ,buffer-var)) (location* ,bp-var)))))))
