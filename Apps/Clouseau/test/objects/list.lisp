;;;; Copyright (C) 2019 Jan Moringen
;;;;
;;;; This library is free software; you can redistribute it and/or
;;;; modify it under the terms of the GNU Library General Public
;;;; License as published by the Free Software Foundation; either
;;;; version 2 of the License, or (at your option) any later version.
;;;;
;;;; This library is distributed in the hope that it will be useful,
;;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;;; Library General Public License for more details.
;;;;
;;;; You should have received a copy of the GNU Library General Public
;;;; License along with this library; if not, write to the
;;;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;;;; Boston, MA  02111-1307  USA.

(cl:in-package #:clouseau.test)

(def-suite* :clouseau.objects.list
  :in :clouseau)

(test list.object-state-class.smoke
  "Test `object-state-class' for list-related objects."

  (object-state-class-cases
   '(()                      inspected-object)

   ;; Small lists
   '((1 . 2)                 clouseau::inspected-improper-list)
   '((1 2)                   clouseau::inspected-proper-list)
   '((1 2 . 3)               clouseau::inspected-improper-list)
   '((1 2 3)                 clouseau::inspected-proper-list)

   ;; Plist
   '((:foo 1)                clouseau::inspected-plist)
   '((:foo 1 :bar 2)         clouseau::inspected-plist)

   ;; Alist
   '(((:foo . 1))            clouseau::inspected-proper-list)
   '(((:foo . 1) (:bar . 2)) clouseau::inspected-alist)))
