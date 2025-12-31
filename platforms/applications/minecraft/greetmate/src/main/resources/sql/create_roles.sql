CREATE TABLE roles (
    id INT(11) NOT NULL AUTO_INCREMENT,
    role INT(11) NOT NULL,
    role_details VARCHAR(100),
    login_text VARCHAR(100),
    logout_text VARCHAR(100),
    kick_text VARCHAR(100),
    ban_text VARCHAR(100),
    update_time DATETIME NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_roles_role (role)
);
