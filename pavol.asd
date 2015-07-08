(in-package :asdf-user)

(defsystem "pavol"
  :description "Simple StumpWM module to interact with pulseaudio."
  :version "1.3.2"
  :author "Diogo Ramos <dfsr@riseup.net>"
  :licence "GPL3+"
  :depends-on ("stumpwm" "cl-ppcre")
  :components ((:file "pavol")))
