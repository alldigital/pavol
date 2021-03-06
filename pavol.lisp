;;; pavol.lisp --- simple StumpWM module to interact with pulseaudio

;;; Copyright (C) 2012-2014 Diogo F. S. Ramos

;;; This program is free software: you can redistribute it and/or
;;; modify it under the terms of the GNU General Public License as
;;; published by the Free Software Foundation, either version 3 of the
;;; License, or (at your option) any later version.

;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; General Public License for more details.

;;; You should have received a copy of the GNU General Public License
;;; along with this program.  If not, see
;;; <http://www.gnu.org/licenses/>.

;;;; Commentary:

;;; This module doesn't intent to substitute complex programs like
;;; pavucontrol but allow a very primitive control over one sink and
;;; applications.

;;; Usage
;;; -----

;;; The following commands are defined:

;;; + pavol-vol+
;;; + pavol-vol-
;;; + pavol-toggle-mute
;;; + pavol-interactive
;;; + pavol-exit-interactive
;;; + pavol-application-list
;;; + pavol-normalize-sink-inputs

;;; The first three commands are supposed to be used using multimedia
;;; keys.  For this, you have to assign the appropriate keys in your
;;; `.stumpwmrc'. For example:

;;;   (define-key *top-map*
;;;               (kbd "XF86AudioRaiseVolume")
;;;               "pavol-vol+")

;;; `pavol-interactive' can be used if you don't have or don't want to
;;; use the media keys.  Once called, you can use `j', `k' and `m'
;;; keys to control the volume and exit the interactive mode using
;;; `ESC', `RET' or `C-g'.

;;; With `pavol-application-list' you can list the running
;;; applications that can have their volume controlled by pulseaudio.
;;; Navigate the menu using `j' and `k' keys and select the desired
;;; application using `RET'.

;;; After changing volumes of applications for a while, they might be
;;; all over the place.  Use `pavol-normalize-sink-inputs' to bring
;;; all of them to the same level of the default sink.

;;; Finally, `pavol-exit-interactive' is a hack to restore the keymap.

;;; Dependencies
;;; ------------

;;; Pavol is known to work with:
;;;
;;; * SBCL 1.1.18
;;; * pacmd 2.0
;;;
;;; pacmd version is the most important because the output of the
;;; command might change from version to version.

;;; Installation
;;; ------------

;;; Pavol is an ASDF system, so you should put it where ASDF can find
;;; and load it with `load-module' or `asdf:load-system'.
;;;
;;; You can also load it directly, using (load "/path/to/pavol.lisp").

;;; Limitations
;;; -----------

;;; As stated before, pavol is a *very* simple module to control a
;;; single sink.  So, if you have more than one sink, it might change
;;; the wrong one.

;;; PulseAudio is a complex system, but pavol will only let you do
;;; three things:

;;; + Increase volume
;;; + Decrease volume
;;; + Mute

;;; Also, by relying on a command line tool, pavol is sensible to
;;; output changes from the tool.

;;;; Code:

(defpackage #:pavol
  (:use #:cl)
  (:import-from #:stumpwm #:defcommand))

(in-package #:pavol)

;;; "pavol" goes here. Hacks and glory await!

(defparameter *normal-volume* 65536
  ;; The name comes from pulseaudio.
  "The maximum value allowed to a volume in pavol.")

(defvar *sink* nil
  "Current sink input.

It is used to make interactive operations possible.")


;;;; Keymaps
(defparameter *interactive-keymap*
  (let ((m (stumpwm:make-sparse-keymap)))
    (labels ((dk (k c)
               (stumpwm:define-key m k c)))
      (dk (stumpwm:kbd "j") "pavol-vol-")
      (dk (stumpwm:kbd "k") "pavol-vol+")
      (dk (stumpwm:kbd "m") "pavol-toggle-mute")
      (dk (stumpwm:kbd "RET") "pavol-exit-interactive")
      (dk (stumpwm:kbd "C-g") "pavol-exit-interactive")
      (dk (stumpwm:kbd "ESC") "pavol-exit-interactive")
      m)))

(defparameter *application-list-keymap*
  (let ((m (stumpwm:make-sparse-keymap)))
    (labels ((dk (k c)
               (stumpwm:define-key m k c)))
      (dk (stumpwm:kbd "j") 'stumpwm::menu-down)
      (dk (stumpwm:kbd "k") 'stumpwm::menu-up)
      m)))


;;;; External command
(defun pacmd (control-string &rest args)
  (stumpwm:run-shell-command
   (apply #'format nil
          (concatenate 'string "pacmd " control-string) args)
   t))


;;;; Generics
(defgeneric volume (sink)
  (:documentation "The SINK volume."))

(defgeneric (setf volume) (percentage sink)
  (:documentation "Set the volume of SINK to PERCENTAGE."))

(defgeneric mute-p (sink)
  (:documentation "Is SINK mute?"))

(defgeneric (setf mute-p) (mute sink)
  (:documentation "Mute SINK."))


;;;; Sink

;;; A "sink" is normally the computer speakers
;;;
;;; There can be more than one Sink

(defclass sink ()
  ((index :initarg :index :reader sink-index)))

(defun number-of-sinks (raw)
  (ppcre:register-groups-bind ((#'parse-integer n))
      (">>>\\s+(\\d+)" raw)
    n))

(defun list-sinks ()
  (let* ((r (pacmd "list-sinks"))
         (n (number-of-sinks r))
         ss)
    (ppcre:do-register-groups (i) ("\\s+index: (\\d+)" r)
      (push (make-instance 'sink-input :index i) ss))
    (assert (= (length ss) n))
    ss))

(defun marked-default-sink-p (&optional pacmd-sink-list)
  "The sink marked with `*'."
  (ppcre:register-groups-bind (i)
      ("(?m:^\\s+[*]\\s+index: (\\d+))"
       (or pacmd-sink-list (pacmd "list-sinks")))
    (make-instance 'sink :index i)))

(define-condition missing-default-sink (error)
  ()
  (:documentation "The default sink can't be determined.")
  (:report "Missing default sink (are you sure pulseaudio is running?)"))

(defun default-sink ()
  "The default sink to operate on.

This is a heuristic."
  ;; A sink marked by `*' is considered the default.  If there is
  ;; none, the first sink encountered is returned.
  (let* ((sink-list (pacmd "list-sinks"))
         (sink (or (marked-default-sink-p sink-list)
                   (ppcre:register-groups-bind (i)
                       ("(?m:^\\s+index: (\\d+))" sink-list)
                     (make-instance 'sink :index i)))))
    (or sink
        (error 'missing-default-sink))))

(defun raw-sink-from-index (index)
  (let ((sinks (pacmd "list-sinks")))
    (multiple-value-bind (s e)
        (ppcre:scan (format nil "(?m:^\\s+[*]?\\s+index: +~a\\s+)" index)
                    sinks)
      (when s
        (subseq sinks
                s
                (ppcre:scan "(?m:^\\s+[*]?\\s+index: +\\d+\\s+)"
                            sinks :start e))))))

(defun sink->raw (sink)
  (or (raw-sink-from-index (sink-index sink))
      (error "invalid sink")))

(defmethod volume ((sink sink))
  (ppcre:register-groups-bind ((#'parse-integer volume))
      ("(?m:^\\s+volume: +(?:front-left: +)\\d+[:/\\s]+(\\d+)%)" (sink->raw sink))
    (if (null volume)
        (error "sink malformed")
      volume)))

(defmethod (setf volume) (percentage (sink sink))
  (assert (<= 0 percentage 100))
  (pacmd "set-sink-volume ~a ~a"
         (sink-index sink)
         (percentage->integer percentage))
  percentage)

(defmethod mute-p ((sink sink))
  (ppcre:register-groups-bind (state)
      ("(?m:^\\s+muted: +(\\w+))"
       (sink->raw sink))
    (not (string= state "no"))))

(defmethod (setf mute-p) (state (sink sink))
  (pacmd "set-sink-mute ~a ~:[0~;1~]" (sink-index sink) state)
  state)


;;;; Sink Input

;;; A sink input is normally a program which is playing some sound.

;;; There can be more than one sink input.

(defclass sink-input ()
  ((index :initarg :index :reader sink-input-index)))

(defun raw-sink-input-from-index (index)
  (let ((sink-inputs (pacmd "list-sink-inputs")))
    (multiple-value-bind (s e)
        (ppcre:scan (format nil "(?m:^\\s+index: +~a\\s+)" index) sink-inputs)
      (when s
        (subseq sink-inputs
                s
                (ppcre:scan "(?m:^\\s+index: +\\d+)" sink-inputs :start e))))))

(defun sink-input->raw (sink-input)
  (or (raw-sink-input-from-index (sink-input-index sink-input))
      (error "invalid sink")))

(defmethod volume ((sink-input sink-input))
  (ppcre:register-groups-bind ((#'parse-integer volume))
      ("(?m:^\\s+volume: +\\d+: +(\\d+)%)"
       (sink-input->raw sink-input))
    (if (null volume)
        (error "sink malformed")
      volume)))

(defmethod (setf volume) (percentage (sink-input sink-input))
  (assert (<= 0 percentage 100))
  (pacmd "set-sink-input-volume ~a ~a"
         (sink-input-index sink-input)
         (percentage->integer percentage))
  percentage)

(defmethod mute-p ((sink-input sink-input))
  (ppcre:register-groups-bind (state)
      ("(?m:^\\s+muted: +(\\w+))"
       (sink-input->raw sink-input))
    (not (string= state "no"))))

(defmethod (setf mute-p) (state (sink-input sink-input))
  (pacmd "set-sink-input-mute ~a ~:[0~;1~]"
         (sink-input-index sink-input)
         state)
  state)

(defun sink-input-name (sink-input)
  "The application name of the sink input."
  (ppcre:register-groups-bind (name)
      ("(?m:^\\s+application.name += +(\".*))"
       (sink-input->raw sink-input))
    (when name (read-from-string name))))

(defun number-of-sink-inputs (raw)
  (or
   (ppcre:register-groups-bind ((#'parse-integer n))
       (">>>\\s+(\\d+)" raw)
     n)
   0))

(defun list-sink-inputs ()
  "A list of the sink inputs available."
  (let* ((r (pacmd "list-sink-inputs"))
         (n (number-of-sink-inputs r))
         ss)
    (cond ((zerop n) nil)
          (t (ppcre:do-register-groups (i) ("\\s+index: (\\d+)" r)
               (push (make-instance 'sink-input :index i) ss))
             (assert (= (length ss) n))
             ss))))

(defun sink-input->alist (sink-input)
  (cons (format nil "~A ~A"
                (sink-input-name sink-input)
                (make-volume-bar (volume sink-input)))
        sink-input))

(defun sink-inputs-selection ()
  (mapcar #'sink-input->alist (list-sink-inputs)))


;;;; Generic sink functions
(defun volume-up (sink percentage)
  (setf (volume sink) (min (+ (volume sink) percentage) 100)))

(defun volume-down (sink percentage)
  (setf (volume sink) (max (- (volume sink) percentage) 0)))

(defun show-volume-bar (sink)
  (let ((percent (volume sink)))
    (funcall (if (interactivep)
                 #'stumpwm::message-no-timeout
                 #'stumpwm:message)
             (format nil "~:[OPEN~;MUTED~]~%~a"
                     (mute-p sink) (make-volume-bar percent)))))


;;;; Interface function
(defun current-sink ()
  "Current sink for interactive use."
  (or *sink* (default-sink)))

(defun vol+ (percentage)
  (let ((sink (current-sink)))
    (volume-up sink percentage)
    (show-volume-bar sink)))

(defun vol- (percentage)
  (let ((sink (current-sink)))
    (volume-down sink percentage)
    (show-volume-bar sink)))

(defun toggle-mute ()
  (let ((sink (current-sink)))
    (setf (mute-p sink) (not (mute-p sink)))
    (show-volume-bar sink)))


;;;; Utility functions
(defun percentage->integer (percentage)
  (truncate (* *normal-volume* percentage) 100))

(defun make-volume-bar (percent)
  "Return a string that represents a volume bar"
  (format nil "^B~3d%^b [^[^7*~a^]]"
          percent (stumpwm::bar percent 50 #\# #\:)))

(defun set-interactive (&optional sink)
  (setf *sink* sink)
  (stumpwm::push-top-map *interactive-keymap*))

(defun unset-interactive ()
  (setf *sink* nil)
  (if (not (interactivep))
      (warn "Interactive is no active.  Did you accidentally tried to exit it?")
    (stumpwm::pop-top-map)))

(defun interactivep ()
  (equal stumpwm:*top-map* *interactive-keymap*))


;;;; Commands
(defcommand pavol-vol+ () ()
  "Increase the volume by 5 points"
  (vol+ 5))

(defcommand pavol-vol- () ()
  "Decrease the volume by 5 points"
  (vol- 5))

(defcommand pavol-toggle-mute () ()
  "Toggle mute"
  (toggle-mute))

(defcommand pavol-exit-interactive () ()
  "Exit the interactive mode for changing the volume"
  (unset-interactive))

(defcommand pavol-interactive () ()
  "Change the volume interactively using `j', `k' and `m' keys"
  (let ((everything-ok nil))
    ;; If something goes wrong -- e.g. there is no default sink -- I
    ;; have to exit the interactive session.
    (unwind-protect
         (progn (set-interactive)
                (show-volume-bar (current-sink))
                (setf everything-ok t))
      (unless everything-ok
        (pavol-exit-interactive)))))

(defcommand pavol-application-list () ()
  "Give the ability to control independent applications.

They are actually input sinks in pulseaudio's terminology."
  (let ((sinks (sink-inputs-selection)))
    (if (null sinks)
        (stumpwm:message "No application is running")
        (let ((sink
               (stumpwm::select-from-menu (stumpwm:current-screen)
                                          sinks nil 0
                                          *application-list-keymap*)))
          (when sink
            (set-interactive (cdr sink))
            (show-volume-bar (cdr sink)))))))

(defcommand pavol-normalize-sink-inputs () ()
  "Set all sink inputs to the volume of the default sink."
  (let ((volume (volume (default-sink))))
    (dolist (sink-input (list-sink-inputs))
      (setf (volume sink-input) volume))))
