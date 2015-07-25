-- I *think* these tables should have an auto_increment field.
ALTER TABLE probe MODIFY rid INT NOT NULL AUTO_INCREMENT;
ALTER TABLE gene MODIFY gid INT NOT NULL AUTO_INCREMENT;
